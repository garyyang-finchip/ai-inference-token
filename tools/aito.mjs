#!/usr/bin/env node
// SPDX-License-Identifier: CC0-1.0
//
// Record identifiers, schema checks and test vectors for AI Inference Token Onchain.
//
//   node aito.mjs id <record.json>     print the identifier of a record
//   node aito.mjs examples             regenerate assets/erc-8506/examples
//   node aito.mjs vectors              regenerate assets/erc-8506/vectors
//   node aito.mjs check                validate examples against the schemas and the vectors
//   node aito.mjs plan <network>       write the records and series of an evidence run (needs DEPLOYER_PK)
//
// The Solidity tests read the vectors and compare them with what the contracts compute,
// so this file and the contracts are two independent implementations of the same rules.

import { readFileSync, writeFileSync, mkdirSync, readdirSync, existsSync } from "node:fs";
import { dirname, join, relative } from "node:path";
import { fileURLToPath } from "node:url";
import { AbiCoder, Interface, TypedDataEncoder, Wallet, SigningKey, keccak256, solidityPackedKeccak256, toUtf8Bytes, encodeBytes32String, toBeHex, zeroPadValue, getAddress, concat } from "ethers";
import Ajv2020 from "ajv/dist/2020.js";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const ASSETS = join(ROOT, "assets", "erc-8506");
const EXAMPLES = join(ASSETS, "examples");
const VECTORS = join(ASSETS, "vectors");
const SCHEMAS = join(ASSETS, "schemas");
const coder = AbiCoder.defaultAbiCoder();

// ---------------------------------------------------------------------------
// Canonical form and identifiers
// ---------------------------------------------------------------------------

/**
 * Canonical form of a record: RFC 8785 (JCS) restricted to the JSON that records may contain.
 * Records carry no floating-point numbers; quantities are decimal strings. Under that
 * restriction JCS reduces to: members sorted by UTF-16 code units, no insignificant
 * whitespace, strings escaped as ECMAScript JSON.stringify does.
 */
export function canonicalize(value) {
  if (value === null) return "null";
  if (typeof value === "boolean") return value ? "true" : "false";
  if (typeof value === "string") return JSON.stringify(value);
  if (typeof value === "number") {
    if (!Number.isSafeInteger(value)) throw new Error(`records carry safe integers only, got ${value}`);
    return String(value);
  }
  if (Array.isArray(value)) return "[" + value.map(canonicalize).join(",") + "]";
  if (typeof value === "object") {
    const keys = Object.keys(value).sort();
    return "{" + keys.map((k) => JSON.stringify(k) + ":" + canonicalize(value[k])).join(",") + "}";
  }
  throw new Error(`unsupported value of type ${typeof value}`);
}

/** Identifier of a record: keccak256 of the UTF-8 bytes of its canonical form. */
export function recordId(record) {
  return keccak256(toUtf8Bytes(canonicalize(record)));
}

const hashText = (text) => keccak256(toUtf8Bytes(text));

/**
 * Root of a batch of records. Leaves are the record identifiers in ascending numerical order,
 * without duplicates, each hashed as keccak256(0x00 || id). A parent is
 * keccak256(0x01 || left || right). A level with an odd number of nodes carries its last node
 * up unchanged. The root of a batch of one record is its leaf.
 */
export function batchRoot(ids) {
  const sorted = [...ids].map((id) => id.toLowerCase()).sort((a, b) => (BigInt(a) < BigInt(b) ? -1 : BigInt(a) > BigInt(b) ? 1 : 0));
  if (sorted.length === 0) throw new Error("a batch has at least one record");
  for (let i = 1; i < sorted.length; i++) if (sorted[i] === sorted[i - 1]) throw new Error(`duplicate identifier ${sorted[i]}`);
  let level = sorted.map((id) => keccak256(concat(["0x00", id])));
  while (level.length > 1) {
    const next = [];
    for (let i = 0; i + 1 < level.length; i += 2) next.push(keccak256(concat(["0x01", level[i], level[i + 1]])));
    if (level.length % 2 === 1) next.push(level[level.length - 1]);
    level = next;
  }
  return level[0];
}

/** The batch vector: the three Unit records of the examples, an odd number on purpose. */
function batchVector(ex) {
  const ids = ["case-a/unit", "case-b/unit", "case-c/unit"].map((name) => recordId(ex[name]));
  const sorted = [...ids].sort((a, b) => (BigInt(a) < BigInt(b) ? -1 : 1));
  return {
    rule: "Leaves: record identifiers ascending, each keccak256(0x00 || id). Parent: keccak256(0x01 || left || right). An odd last node is carried up unchanged.",
    kind: "unit",
    ids: sorted,
    leaves: sorted.map((id) => keccak256(concat(["0x00", id]))),
    root: batchRoot(ids),
  };
}

// ---------------------------------------------------------------------------
// Fixed test material. These keys are public test keys and must never hold value.
// ---------------------------------------------------------------------------

const CHAIN_ID = 11155111;
const LEDGER = getAddress("0xa170000000000000000000000000000000000001");
const T0 = 1_800_000_000; // 2027-01-15T08:00:00Z

const key = (n) => zeroPadValue(toBeHex(n), 32);
const KEYS = {
  supplier: key(0xa11ce),
  distributor: key(0xd157),
  holder: key(0xb0b),
  holder2: key(0xb0b2),
  consumer: key(0xc0ffee),
  alpha: key(0xa1fa),
  beta: key(0xbe7a),
  gamma: key(0x6a33a),
  assessor: key(0x5e501),
};
const ADDR = Object.fromEntries(Object.entries(KEYS).map(([name, k]) => [name, new Wallet(k).address]));
const iso = (t) => new Date(t * 1000).toISOString().replace(".000Z", "Z");

/** Everything the example records depend on. The default is the fixed material of the vectors. */
const DEFAULT_CONTEXT = { chainId: CHAIN_ID, addr: ADDR, t0: T0, objectionWindow: 600, maxHoldA: 900, maxHoldB: 600 };

// ---------------------------------------------------------------------------
// Example records
// ---------------------------------------------------------------------------

export function buildExamples(ctx = DEFAULT_CONTEXT) {
  const ex = {};
  const ADDR = ctx.addr;
  const caip = (address) => `eip155:${ctx.chainId}:${address}`;
  const validFrom = iso(ctx.t0);
  const validUntilA = iso(ctx.t0 + 90 * 86400);
  const validUntilB = iso(ctx.t0 + 30 * 86400);
  const windowSeconds = String(ctx.objectionWindow);

  // ----- Case A: a supplier's quota -----------------------------------------
  ex["case-a/unit"] = {
    aito: "1",
    kind: "unit",
    name: "Text inference tokens, output-equivalent",
    description: "Text tokens of one named counter. One denomination unit is the supply of one output token.",
    quantityKind: "inference-usage",
    modality: "text",
    basis: "Tokens as counted per request by the counter named in counterRef.",
    denomination: "One denomination unit equals one unit of the component output.",
    components: [
      { id: "input", description: "Tokens read from the request, including system prompt and tool results, excluding tokens served from cache." },
      { id: "output", description: "Tokens generated, including reasoning tokens whether or not they are returned to the caller." },
      { id: "cache_read", description: "Request tokens served from a prompt cache." },
    ],
    relations: [
      { a: "input", b: "cache_read", relation: "disjoint" },
      { a: "input", b: "output", relation: "additive" },
      { a: "cache_read", b: "output", relation: "additive" },
    ],
    boundary: { scope: "request", counted: ["system-prompt", "tool-results", "reasoning"], notCounted: ["provider-retries"] },
    precision: "1",
    rounding: "up",
    counterRef: { name: "example-bpe", version: "2026-03", digest: hashText("example-bpe 2026-03 vocabulary") },
  };

  ex["case-a/grade"] = {
    aito: "1",
    kind: "grade",
    name: "Fixed open-weight model, 128k context, no retention",
    description: "Supply of text inference by one fixed model. Promises and duties are listed; measured values are in Assessments.",
    unit: recordId(ex["case-a/unit"]),
    ordering: "none",
    executionObject: {
      kind: "fixed-model",
      identity: { weightsDigest: hashText("example open-weight model, revision 7"), quantization: "none" },
      config: { reasoningBudget: "medium", sampling: "caller-controlled", systemPromptPolicy: "caller-only", tools: "none" },
    },
    requirements: [
      { id: "context-window", family: "delivery", statement: "Context window of at least 128000 tokens.", comparator: ">=", value: "128000", scope: "per-request", compensable: false },
      { id: "first-token-latency", family: "delivery", statement: "95th percentile time to first token of at most 3000 milliseconds.", comparator: "<=", value: "3000", scope: "window", window: "PT1H", compensable: true },
    ],
    obligations: [
      { id: "no-retention", family: "terms", statement: "Requests and outputs are not retained after the response is delivered.", obligor: "responsible-party", compensable: false },
    ],
    verificationPolicy: {
      origin: { evidence: "self-attested" },
      metering: { evidence: "self-attested", acceptance: "optimistic" },
      execution: { evidence: "self-attested" },
      quality: { evidence: "third-party-assessed" },
      deliverySettlement: { evidence: "onchain" },
    },
    attributes: { capability: "undeclared", efficiency: "undeclared", robustness: "undeclared", speciality: "undeclared", energy: "undeclared" },
  };

  const basisA = {
    id: "own-capacity-2027q1",
    origin: "own-capacity",
    description: "Inference capacity the supplier operates itself.",
    issuanceRight: "issuer",
    supplyObligation: "responsible-party",
    authorization: "not-applicable",
    quantityBound: "10000000",
    timeBound: { notBefore: validFrom, notAfter: validUntilA },
    doubleIssuanceControl: "The quantity bound is shared by every series that cites this basis.",
    backing: "none",
  };
  ex["case-a/source"] = {
    aito: "1",
    kind: "source",
    name: "Supplier A, own capacity",
    issuer: caip(ADDR.supplier),
    responsibleParty: caip(ADDR.supplier),
    fulfillers: [caip(ADDR.supplier)],
    issuanceBases: [basisA],
    capacity: { mode: "best-effort", total: "10000000" },
    exclusivity: "undeclared",
    collateral: "none",
  };

  ex["case-a/terms"] = {
    aito: "1",
    kind: "terms",
    name: "Supplier A inference quota, 90 days",
    description: "Stock quota of text inference, consumable for 90 days, transferable.",
    profile: "stock-quota",
    denomination: "One unit entitles its holder to the supply of one output token, or the scheduled equivalent, under the named Grade.",
    quantity: { form: "stock", cap: "10000000" },
    time: { validFrom, validUntil: validUntilA, period: "none", reservation: "none" },
    transferRule: { transferable: true, restrictions: "none" },
    issuanceRule: { mechanisms: ["purchase"], issuer: "issuer" },
    consumptionRule: {
      authorizedBy: "holder",
      heldBy: "registered-fulfiller",
      maxHoldSeconds: String(ctx.maxHoldA),
      metering: { by: "fulfiller", tolerance: "none" },
      acceptance: { rule: "optimistic", objectionWindowSeconds: windowSeconds, resolver: "none", onObjection: "release" },
      executionTrigger: "The fulfiller starts execution after the hold is included in a block.",
      riskOfReorganization: "fulfiller",
    },
    outcomeCharging: {
      completed: "all components",
      partial: "all components, as delivered",
      refused: "input only",
      timedOut: "nothing",
      cancelledByConsumer: "all components, as incurred",
      providerError: "nothing",
    },
    substitutionPolicy: { allowed: false },
    remedies: { onExpiry: "lapse", onSupplyFailure: "none", disputes: "none beyond the objection rule" },
    extensions: [],
  };

  // ----- Case B: an agent issues against its own capacity ---------------------
  ex["case-b/unit"] = {
    aito: "1",
    kind: "unit",
    name: "Text inference tokens of agent alpha",
    description: "Text tokens of the tokenizer shipped with the model agent alpha runs.",
    quantityKind: "inference-usage",
    modality: "text",
    basis: "Tokens as counted per request by the counter named in counterRef.",
    denomination: "One denomination unit equals one unit of the component output.",
    components: [
      { id: "input", description: "Tokens read from the request." },
      { id: "output", description: "Tokens generated. The model has no separate reasoning tokens." },
    ],
    relations: [{ a: "input", b: "output", relation: "additive" }],
    boundary: { scope: "request", counted: ["system-prompt"], notCounted: ["provider-retries"] },
    precision: "1",
    rounding: "up",
    counterRef: { name: "alpha-tokenizer", version: "1", digest: hashText("alpha tokenizer vocabulary, version 1") },
  };

  ex["case-b/grade"] = {
    aito: "1",
    kind: "grade",
    name: "Small open-weight model run by agent alpha, 4-bit, 32k context",
    description: "Every proposition is self-attested. Nothing is promised beyond the execution object.",
    unit: recordId(ex["case-b/unit"]),
    ordering: "none",
    executionObject: {
      kind: "fixed-model",
      identity: { weightsDigest: hashText("small open-weight model, revision 2"), quantization: "4-bit" },
      config: { reasoningBudget: "none", sampling: "caller-controlled", systemPromptPolicy: "caller-only", tools: "none" },
    },
    requirements: [
      { id: "context-window", family: "delivery", statement: "Context window of at least 32000 tokens.", comparator: ">=", value: "32000", scope: "per-request", compensable: false },
    ],
    obligations: [],
    verificationPolicy: {
      origin: { evidence: "self-attested" },
      metering: { evidence: "self-attested", acceptance: `consumer signature, or no objection within ${windowSeconds} seconds` },
      execution: { evidence: "self-attested" },
      quality: { evidence: "self-attested" },
      deliverySettlement: { evidence: "onchain" },
    },
    attributes: { capability: "undeclared", efficiency: "undeclared", robustness: "undeclared", speciality: "undeclared", energy: "undeclared" },
  };

  const basisB = {
    id: "alpha-own-hardware",
    origin: "own-capacity",
    description: "A single machine operated by agent alpha.",
    issuanceRight: "issuer",
    supplyObligation: "responsible-party",
    authorization: "not-applicable",
    quantityBound: "5000000",
    timeBound: { notBefore: validFrom, notAfter: validUntilB },
    doubleIssuanceControl: "This basis is cited by one series only.",
    backing: "none",
  };
  ex["case-b/source"] = {
    aito: "1",
    kind: "source",
    name: "Agent alpha, own hardware",
    issuer: caip(ADDR.alpha),
    responsibleParty: caip(ADDR.alpha),
    fulfillers: [caip(ADDR.alpha)],
    issuanceBases: [basisB],
    capacity: { mode: "best-effort", total: "5000000" },
    exclusivity: "undeclared",
    collateral: "none",
  };

  ex["case-b/terms"] = {
    aito: "1",
    kind: "terms",
    name: "Agent alpha inference quota, 30 days",
    description: "Stock quota of text inference by agent alpha, consumable for 30 days, transferable.",
    profile: "stock-quota",
    denomination: "One unit entitles its holder to the supply of one output token, or the scheduled equivalent, under the named Grade.",
    quantity: { form: "stock", cap: "5000000" },
    time: { validFrom, validUntil: validUntilB, period: "none", reservation: "none" },
    transferRule: { transferable: true, restrictions: "none" },
    issuanceRule: { mechanisms: ["purchase"], issuer: "issuer" },
    consumptionRule: {
      authorizedBy: "holder",
      heldBy: "registered-fulfiller",
      maxHoldSeconds: String(ctx.maxHoldB),
      metering: { by: "fulfiller", tolerance: "none" },
      acceptance: { rule: "optimistic", objectionWindowSeconds: windowSeconds, resolver: "none", onObjection: "release" },
      executionTrigger: "The fulfiller starts execution after the hold is included in a block.",
      riskOfReorganization: "fulfiller",
    },
    outcomeCharging: {
      completed: "all components",
      partial: "all components, as delivered",
      refused: "input only",
      timedOut: "nothing",
      cancelledByConsumer: "all components, as incurred",
      providerError: "nothing",
    },
    substitutionPolicy: { allowed: false },
    remedies: { onExpiry: "lapse", onSupplyFailure: "none", disputes: "none beyond the objection rule" },
    extensions: [],
  };

  // ----- Case C: inference that is not counted in text tokens -----------------
  ex["case-c/unit"] = {
    aito: "1",
    kind: "unit",
    name: "Image inference, kilopixel-steps",
    description: "Diffusion work measured as output kilopixels times sampling steps, with upscaling counted separately.",
    quantityKind: "inference-usage",
    modality: "image",
    basis: "Kilopixels of the generated image multiplied by the number of sampling steps, per request, rounded up to a whole kilopixel-step.",
    denomination: "One denomination unit equals one unit of the component kilopixel_steps.",
    components: [
      { id: "kilopixel_steps", description: "Output kilopixels multiplied by sampling steps." },
      { id: "upscale_kilopixels", description: "Kilopixels added by an upscaling pass." },
    ],
    relations: [{ a: "kilopixel_steps", b: "upscale_kilopixels", relation: "additive" }],
    boundary: { scope: "request", counted: ["all sampling steps"], notCounted: ["safety-filter passes"] },
    precision: "1",
    rounding: "up",
  };

  // ----- Optional modules ------------------------------------------------------
  ex["optional/method"] = {
    aito: "1",
    kind: "method",
    name: "Conditional calibration against a reference workload",
    description: "Finds how many native units each execution object needs to reach the same supply level on a pinned workload.",
    methodType: "conditional-calibration",
    basisSide: "output",
    inputs: ["workload digest D", "compute budget B", "quality requirement Q", "delivery constraint S", "execution objects under comparison"],
    outputs: ["native units per reference task, per execution object", "error interval"],
    applicability: "Text inference on the task domain of the pinned workload. Not valid outside that domain.",
    limitations: [
      "Coefficients do not carry over to other workloads, budgets or quality requirements.",
      "The method compares supply. It grants no right to issue and transfers no obligation.",
    ],
  };

  ex["optional/assessment"] = {
    aito: "1",
    kind: "assessment",
    name: "Pass rate of the Case A execution object on the reference workload",
    subject: { grade: recordId(ex["case-a/grade"]), executionObject: "fixed-model" },
    assessor: caip(ADDR.assessor),
    standing: "third-party",
    metric: { family: "capability", name: "reference-workload-pass-rate", version: "1" },
    value: "0.93",
    state: "measured",
    conditions: {
      taskDomain: "software maintenance tasks of the pinned workload",
      inputConditions: "inputs up to 20000 tokens",
      computeBudget: "medium reasoning budget",
      executionConfig: "as stated in the Grade",
      runConditions: "three runs per task",
    },
    method: recordId(ex["optional/method"]),
    scope: "1200 tasks, three runs each",
    uncertainty: "0.012",
    asOf: "2027-01-10T00:00:00Z",
    validUntil: "2027-04-10T00:00:00Z",
    evidence: hashText("assessment run log, 2027-01-10"),
  };

  ex["optional/method-application"] = {
    aito: "1",
    kind: "method-application",
    name: "Calibration of the Case A execution object, first quarter of 2027",
    method: recordId(ex["optional/method"]),
    parameters: {
      workloadDigest: hashText("reference workload, 1200 tasks, revision 3"),
      computeBudget: "medium reasoning budget",
      qualityRequirement: "pass rate of at least 0.90",
      deliveryConstraint: "95th percentile time to first token of at most 3000 milliseconds",
    },
    subjects: [{ grade: recordId(ex["case-a/grade"]) }],
    inputSnapshot: [recordId(ex["optional/assessment"])],
    conditions: "Valid for the task domain of the pinned workload only.",
    validFrom,
    validUntil: validUntilA,
    recalibration: ["a new revision of the workload", "a change of the execution object", "expiry of an input Assessment"],
    result: { nativeUnitsPerReferenceTask: "1250", errorInterval: "0.05" },
  };

  return ex;
}

/** Identifier of an issuance basis: keccak256 of the canonical form of its entry in the Source record. */
export const basisRef = (source, index = 0) => recordId(source.issuanceBases[index]);

// ---------------------------------------------------------------------------
// On-chain encodings
// ---------------------------------------------------------------------------

const SERIES_TUPLE =
  "tuple(address issuer,address responsibleParty,bytes32 unit,bytes32 grade,bytes32 source,bytes32 termsHash," +
  "uint256 cap,uint64 validFrom,uint64 validUntil,bool transferable,bool scheduleMutable,bool roundUp," +
  "uint8 acceptanceRule,uint32 objectionWindow,uint32 resolutionWindow,uint32 maxHoldDuration,address resolver," +
  "bytes32[] components,uint256[] weights,uint256[] outcomeMasks,tuple(bytes32 id,bool critical,bytes data)[] extensions)";

export function seriesIdOf(terms) {
  return keccak256(coder.encode([SERIES_TUPLE], [terms]));
}

const EIP712_TYPES = {
  Authorization: [
    { name: "holder", type: "address" },
    { name: "consumer", type: "address" },
    { name: "seriesId", type: "uint256" },
    { name: "cap", type: "uint256" },
    { name: "validAfter", type: "uint64" },
    { name: "validUntil", type: "uint64" },
    { name: "scope", type: "bytes32" },
    { name: "nonce", type: "uint256" },
  ],
  ConsumptionRequest: [
    { name: "authorizationId", type: "bytes32" },
    { name: "requestId", type: "bytes32" },
    { name: "fulfiller", type: "address" },
    { name: "maxAmount", type: "uint256" },
    { name: "holdUntil", type: "uint64" },
    { name: "scope", type: "bytes32" },
  ],
  UsageAcceptance: [
    { name: "requestKey", type: "bytes32" },
    { name: "claimHash", type: "bytes32" },
    { name: "amount", type: "uint256" },
  ],
};
const only = (name) => ({ [name]: EIP712_TYPES[name] });
const sign = (privateKey, digest) => new SigningKey(privateKey).sign(digest).serialized;
const ZERO32 = "0x" + "00".repeat(32);

function textTermsA(ex, ctx = DEFAULT_CONTEXT) {
  return {
    issuer: ctx.addr.supplier,
    responsibleParty: ctx.addr.supplier,
    unit: recordId(ex["case-a/unit"]),
    grade: recordId(ex["case-a/grade"]),
    source: recordId(ex["case-a/source"]),
    termsHash: recordId(ex["case-a/terms"]),
    cap: "10000000",
    validFrom: String(ctx.t0),
    validUntil: String(ctx.t0 + 90 * 86400),
    transferable: true,
    scheduleMutable: false,
    roundUp: true,
    acceptanceRule: 1,
    objectionWindow: ctx.objectionWindow,
    resolutionWindow: 0,
    maxHoldDuration: ctx.maxHoldA,
    resolver: "0x0000000000000000000000000000000000000000",
    components: ["input", "output", "cache_read"].map(encodeBytes32String),
    weights: ["250000", "1000000", "25000"],
    outcomeMasks: ["7", "7", "1", "0", "7", "0"],
    extensions: [],
  };
}

function textTermsB(ex, ctx = DEFAULT_CONTEXT) {
  return {
    issuer: ctx.addr.alpha,
    responsibleParty: ctx.addr.alpha,
    unit: recordId(ex["case-b/unit"]),
    grade: recordId(ex["case-b/grade"]),
    source: recordId(ex["case-b/source"]),
    termsHash: recordId(ex["case-b/terms"]),
    cap: "5000000",
    validFrom: String(ctx.t0),
    validUntil: String(ctx.t0 + 30 * 86400),
    transferable: true,
    scheduleMutable: false,
    roundUp: true,
    acceptanceRule: 1,
    objectionWindow: ctx.objectionWindow,
    resolutionWindow: 0,
    maxHoldDuration: ctx.maxHoldB,
    resolver: "0x0000000000000000000000000000000000000000",
    components: ["input", "output"].map(encodeBytes32String),
    weights: ["200000", "1000000"],
    outcomeMasks: ["3", "3", "1", "0", "3", "0"],
    extensions: [],
  };
}

export function buildVectors(ex) {
  const caip = (address) => `eip155:${CHAIN_ID}:${address}`;
  const records = Object.entries(ex).map(([name, record]) => ({
    file: `examples/${name}.json`,
    kind: record.kind,
    id: recordId(record),
  }));
  const canonicalSample = {
    file: "examples/case-b/unit.json",
    canonical: canonicalize(ex["case-b/unit"]),
    id: recordId(ex["case-b/unit"]),
  };

  const termsA = textTermsA(ex);
  const termsB = textTermsB(ex);
  const seriesA = seriesIdOf(termsA);
  const seriesB = seriesIdOf(termsB);
  const series = {
    note: "seriesId is keccak256(abi.encode(terms)) read as an unsigned integer.",
    caseA: { terms: termsA, seriesId: seriesA, seriesIdDecimal: BigInt(seriesA).toString(), basisRef: basisRef(ex["case-a/source"]) },
    caseB: { terms: termsB, seriesId: seriesB, seriesIdDecimal: BigInt(seriesB).toString(), basisRef: basisRef(ex["case-b/source"]) },
  };

  // Case B, signed with the public test keys, for a ledger at a fixed address on a fixed chain.
  const domain = { name: "AITO", version: "1", chainId: CHAIN_ID, verifyingContract: LEDGER };
  const authorization = {
    holder: ADDR.beta,
    consumer: ADDR.gamma,
    seriesId: BigInt(seriesB).toString(),
    cap: "50000",
    validAfter: String(T0),
    validUntil: String(T0 + 7 * 86400),
    scope: ZERO32,
    nonce: "1",
  };
  const authorizationId = TypedDataEncoder.hash(domain, only("Authorization"), authorization);
  const requestId = hashText("case-b/r1");
  const request = {
    authorizationId,
    requestId,
    fulfiller: ADDR.alpha,
    maxAmount: "3000",
    holdUntil: String(T0 + 600),
    scope: ZERO32,
  };
  const requestDigest = TypedDataEncoder.hash(domain, only("ConsumptionRequest"), request);
  const requestKey = keccak256(coder.encode(["address", "bytes32"], [ADDR.gamma, requestId]));

  const usage = ["2000", "1400"];
  const outcome = 0; // Completed
  const evidenceRoot = hashText("alpha signed statement");
  const claimHash = keccak256(coder.encode(["bytes32", "uint256[]", "uint8", "bytes32"], [requestKey, usage, outcome, evidenceRoot]));
  const computed = "1800"; // 1400 + 0.2 x 2000
  const acceptance = { requestKey, claimHash, amount: computed };
  const acceptanceDigest = TypedDataEncoder.hash(domain, only("UsageAcceptance"), acceptance);
  const released = "1200";
  const receiptHash = keccak256(
    coder.encode(
      ["uint256", "address", "bytes32", "uint256", "address", "address", "address", "bytes32", "bytes32", "uint256", "uint256"],
      [CHAIN_ID, LEDGER, requestKey, seriesB, ADDR.beta, ADDR.gamma, ADDR.alpha, authorizationId, claimHash, computed, released],
    ),
  );

  const eip712 = {
    note: "Typed data of Case B for a ledger at a fixed address. The keys are public test keys.",
    time: String(T0),
    domain,
    domainSeparator: TypedDataEncoder.hashDomain(domain),
    typeHashes: {
      Authorization: hashText(TypedDataEncoder.from(only("Authorization")).encodeType("Authorization")),
      ConsumptionRequest: hashText(TypedDataEncoder.from(only("ConsumptionRequest")).encodeType("ConsumptionRequest")),
      UsageAcceptance: hashText(TypedDataEncoder.from(only("UsageAcceptance")).encodeType("UsageAcceptance")),
    },
    accounts: { alpha: ADDR.alpha, beta: ADDR.beta, gamma: ADDR.gamma },
    authorization,
    authorizationId,
    holderSignature: sign(KEYS.beta, authorizationId),
    request,
    requestDigest,
    consumerSignature: sign(KEYS.gamma, requestDigest),
    requestKey,
    usage,
    outcome,
    evidenceRoot,
    claimHash,
    computed,
    acceptanceDigest,
    acceptanceSignature: sign(KEYS.gamma, acceptanceDigest),
    deducted: computed,
    released,
    receiptHash,
  };

  // The off-chain form of the receipt of the same request.
  const receipt = {
    aito: "1",
    kind: "receipt",
    name: "Receipt of request r1 of Case B",
    request: {
      requestId,
      requestKey,
      ledger: caip(LEDGER),
      seriesId: BigInt(seriesB).toString(),
      holder: caip(ADDR.beta),
      consumer: caip(ADDR.gamma),
      fulfiller: caip(ADDR.alpha),
      authorizationId,
      unit: recordId(ex["case-b/unit"]),
    },
    claim: { by: caip(ADDR.alpha), usage, outcome: "completed", executionObject: "fixed-model", claimHash },
    evidence: [
      {
        proposition: "metering",
        mechanism: "statement signed by the fulfiller",
        reliesOn: "the fulfiller's own count",
        doesNotShow: "that the declared model produced the output, or that no undisclosed computation took place",
        ref: evidenceRoot,
      },
    ],
    acceptance: { rule: "optimistic, accepted early by consumer signature", by: caip(ADDR.gamma), amount: computed },
    effect: { deducted: computed, released, receiptHash },
  };

  return { records, canonicalSample, series, eip712, receipt, interfaces: interfaceIds() };
}

/** ERC-165 identifiers computed from the compiled ABIs, when the contracts have been built. */
function interfaceIds() {
  const names = ["IAITORecords", "IAITOInstrument", "IAITOConsumption", "IAITOBinding", "IAITOWrapper20", "IAITOPeriodic"];
  const out = {};
  for (const name of names) {
    const artifact = join(ROOT, "out", `${name}.sol`, `${name}.json`);
    if (!existsSync(artifact)) continue;
    const abi = JSON.parse(readFileSync(artifact, "utf8")).abi;
    const iface = new Interface(abi);
    let id = 0n;
    iface.forEachFunction((f) => {
      id ^= BigInt(f.selector);
    });
    out[name] = zeroPadValue(toBeHex(id), 4);
  }
  return out;
}


// ---------------------------------------------------------------------------
// Evidence plan: the records and series of a live run, for the accounts of that run
// ---------------------------------------------------------------------------

const NETWORKS = { anvil: 31337, sepolia: 11155111 };
const ACTORS = ["supplier", "distributor", "holder", "holder2", "consumer", "alpha", "beta", "gamma"];

/** The accounts of a run are derived from the deployer key, as script/AITOEvidence.s.sol does. */
const actorKey = (deployerKey, label) => solidityPackedKeccak256(["uint256", "string"], [deployerKey, label]);

function cmdPlan(network, baseUri) {
  const chainId = NETWORKS[network];
  if (!chainId) throw new Error(`unknown network ${network}`);
  const deployerKey = process.env.DEPLOYER_PK;
  if (!deployerKey) throw new Error("set DEPLOYER_PK");
  // The series of a run are valid from the start of the current UTC day, so that the run can
  // consume at once. A start in the future would make every hold fail until then.
  const t0 = Number(process.env.PLAN_T0 ?? Math.floor(Date.now() / 86400000) * 86400);
  if (t0 > Math.floor(Date.now() / 1000)) throw new Error(`PLAN_T0 ${iso(t0)} is in the future`);
  const addr = Object.fromEntries(ACTORS.map((label) => [label, new Wallet(actorKey(deployerKey, label)).address]));
  addr.assessor = addr.consumer;
  // A live run uses a short objection window and long holds, so that slow blocks cannot break it.
  const ctx = { chainId, addr, t0, objectionWindow: 120, maxHoldA: 3600, maxHoldB: 3600 };
  const ex = buildExamples(ctx);

  const dir = join(ROOT, "deployments", network);
  const uri = (name) => `${baseUri}deployments/${network}/records/${name}.json`;
  const side = (prefix, terms) => {
    const names = ["unit", "grade", "source", "terms"];
    for (const n of names) writeJson(join(dir, "records", `${prefix}-${n}.json`), ex[`${prefix}/${n}`]);
    return {
      unit: terms.unit,
      grade: terms.grade,
      source: terms.source,
      termsHash: terms.termsHash,
      unitURI: uri(`${prefix}-unit`),
      gradeURI: uri(`${prefix}-grade`),
      sourceURI: uri(`${prefix}-source`),
      termsURI: uri(`${prefix}-terms`),
      basisRef: basisRef(ex[`${prefix}/source`]),
      terms,
      seriesId: BigInt(seriesIdOf(terms)).toString(),
    };
  };
  const plan = {
    network,
    chainId,
    deployer: new Wallet(deployerKey).address,
    validFrom: iso(t0),
    actors: Object.fromEntries(ACTORS.map((label) => [label, addr[label]])),
    caseA: side("case-a", textTermsA(ex, ctx)),
    caseB: side("case-b", textTermsB(ex, ctx)),
  };
  writeJson(join(dir, "plan.json"), plan);
  console.log(`wrote deployments/${network}/plan.json for deployer ${plan.deployer}`);
}

// ---------------------------------------------------------------------------
// Commands
// ---------------------------------------------------------------------------

const writeJson = (path, value) => {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, JSON.stringify(value, null, 2) + "\n");
};
const readJson = (path) => JSON.parse(readFileSync(path, "utf8"));

function cmdExamples() {
  const ex = buildExamples();
  for (const [name, record] of Object.entries(ex)) writeJson(join(EXAMPLES, `${name}.json`), record);
  console.log(`wrote ${Object.keys(ex).length} example records`);
}

function cmdVectors() {
  const ex = buildExamples();
  const v = buildVectors(ex);
  writeJson(join(EXAMPLES, "case-b", "receipt.json"), v.receipt);
  const receiptEntry = { file: "examples/case-b/receipt.json", kind: "receipt", id: recordId(v.receipt) };
  writeJson(join(VECTORS, "records.json"), {
    rule: "id = keccak256(UTF-8 bytes of the canonical form). Canonical form: RFC 8785, with numbers restricted to safe integers.",
    canonicalSample: v.canonicalSample,
    records: [...v.records, receiptEntry],
    batch: batchVector(ex),
  });
  writeJson(join(VECTORS, "series.json"), v.series);
  writeJson(join(VECTORS, "typed-data.json"), v.eip712);
  if (Object.keys(v.interfaces).length) {
    writeJson(join(VECTORS, "interfaces.json"), {
      rule: "XOR of the function selectors of the interface (ERC-165).",
      ...v.interfaces,
      extensionRule: "keccak256 of the UTF-8 name of the extension.",
      extensions: {
        "aito.profile.periodic-allowance.v1": hashText("aito.profile.periodic-allowance.v1"),
        "aito.profile.reserved-capacity.v1": hashText("aito.profile.reserved-capacity.v1"),
      },
    });
  }
  console.log("wrote vectors");
}

function listJson(dir) {
  const out = [];
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const p = join(dir, entry.name);
    if (entry.isDirectory()) out.push(...listJson(p));
    else if (entry.name.endsWith(".json")) out.push(p);
  }
  return out.sort();
}

function cmdCheck() {
  const ajv = new Ajv2020({ allErrors: true, strict: false });
  const validators = {};
  for (const file of readdirSync(SCHEMAS)) {
    const schema = readJson(join(SCHEMAS, file));
    validators[schema.properties.kind.const] = ajv.compile(schema);
  }
  let failures = 0;
  const fail = (message) => {
    failures++;
    console.error("FAIL " + message);
  };

  const vectors = readJson(join(VECTORS, "records.json"));
  const expected = Object.fromEntries(vectors.records.map((r) => [r.file, r]));
  const files = listJson(EXAMPLES);
  for (const file of files) {
    const rel = relative(ASSETS, file).split("\\").join("/");
    const record = readJson(file);
    const validate = validators[record.kind];
    if (!validate) fail(`${rel}: unknown kind ${record.kind}`);
    else if (!validate(record)) fail(`${rel}: ${ajv.errorsText(validate.errors)}`);
    const want = expected[rel];
    if (!want) fail(`${rel}: no vector`);
    else if (want.id !== recordId(record)) fail(`${rel}: id ${recordId(record)} differs from vector ${want.id}`);
  }
  if (files.length !== vectors.records.length) fail(`examples (${files.length}) and vectors (${vectors.records.length}) differ in number`);
  if (keccak256(toUtf8Bytes(vectors.canonicalSample.canonical)) !== vectors.canonicalSample.id) fail("canonical sample does not hash to its id");

  // The vectors must be exactly what this tool derives from the examples on disk.
  const ex = Object.fromEntries(
    files.filter((f) => !f.endsWith("receipt.json")).map((f) => [relative(EXAMPLES, f).split("\\").join("/").replace(/\.json$/, ""), readJson(f)]),
  );
  const fresh = buildVectors(ex);
  const same = (a, b) => canonicalize(a) === canonicalize(b);
  if (!same(fresh.series, readJson(join(VECTORS, "series.json")))) fail("series.json is stale");
  if (!same(fresh.eip712, readJson(join(VECTORS, "typed-data.json")))) fail("typed-data.json is stale");
  if (!same(fresh.receipt, readJson(join(EXAMPLES, "case-b", "receipt.json")))) fail("examples/case-b/receipt.json is stale");
  if (!same(batchVector(ex), vectors.batch)) fail("records.json: the batch vector is stale");

  // Every reference between example records resolves to another example record.
  const ids = new Set(vectors.records.map((r) => r.id));
  for (const [name, record] of Object.entries(ex)) {
    for (const ref of [record.unit, record.method, record.subject?.grade, ...(record.inputSnapshot ?? [])]) {
      if (ref && !ids.has(ref)) fail(`${name}: reference ${ref} does not resolve`);
    }
  }

  if (failures) {
    console.error(`${failures} failure(s)`);
    process.exit(1);
  }
  console.log(`ok: ${files.length} records valid, identifiers and vectors consistent`);
}

const [command, argument, extra] = process.argv.slice(2);
const DEFAULT_BASE_URI = "https://raw.githubusercontent.com/garyyang-finchip/ai-inference-token/main/";
if (command === "id") console.log(recordId(readJson(argument)));
else if (command === "plan") cmdPlan(argument ?? "anvil", extra ?? DEFAULT_BASE_URI);
else if (command === "examples") cmdExamples();
else if (command === "vectors") cmdVectors();
else if (command === "check") cmdCheck();
else if (command) {
  console.error("usage: node aito.mjs id <record.json> | examples | vectors | check | plan <anvil|sepolia> [baseURI]");
  process.exit(2);
}
