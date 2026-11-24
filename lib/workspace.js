const task = (id, week, title, detail) => ({
  id, kind: "task", week, title, detail, status: "todo"
});

const starters = [
  task("plan-terms", 1, "Explain LLM, VLM and VLA with one example", "Watch the first 12 minutes of the LLM introduction and look at the RT-2 demos. Draw camera image + instruction → policy → robot action. Write three sentences in the journal."),
  task("plan-scope", 1, "Pick one greenhouse task and check available equipment", "Start with a supervised camera inspection of one tomato plant or row. Ask your supervisors which greenhouse, camera, robot, Jetson model, and datasets you can access. Confirm the actual review date."),
  task("plan-notebook", 1, "Run one small inference notebook", "Try a pretrained model in Kaggle or on CPU. Record the input, output, model, and runtime. Use this exercise to distinguish training, fine-tuning, and inference."),
  task("plan-papers", 2, "Compare four papers in a reading matrix", "Read RT-2, OpenVLA, SmolVLA, and AGRI-BT. For each, log task, inputs, outputs, dataset, hardware, metrics, and one limitation. Start with the abstract, one figure, and the results."),
  task("plan-protocol", 2, "Sketch a baseline and an evaluation plan", "Compare a simple detector and fixed inspection policy with a pretrained VLA candidate. Keep the images, instructions, and success criteria consistent. Define what counts as a successful inspection before choosing the model."),
  task("plan-edge", 3, "Map the NVIDIA stack and profile a small baseline", "Identify Jetson and JetPack versions if hardware is available. Learn what CUDA, cuDNN, TensorRT, and tegrastats do. Log warm runs, latency, memory, and power if measurable. Record unavailable metrics explicitly."),
  task("plan-optimize", 3, "Plan one compute and energy comparison", "Compare one change, such as lower image resolution or a supported lower precision, against the same baseline. Track task success, post-warmup latency (median and p95), peak memory, and joules per trial if measured. A desktop run is a rehearsal for Jetson."),
  task("plan-outline", 4, "Draft the article skeleton", "Write a working title, problem, related work, gap to verify, research question, methods, planned evaluation, limitations, and references. Leave measured results as placeholders until experiments are run."),
  task("plan-review", 4, "Prepare the supervisor review", "Bring the outline, reading matrix, one pipeline diagram, and a short list of equipment or data decisions. Ask for approval of the greenhouse task and baseline."),
  {
    id: "meeting-supervisors", kind: "journal", title: "Supervisor meeting",
    detail: "Discussed VLA and VLM software and hardware, LLMs and text generation, free notebook resources (interpreted as Kaggle), NVIDIA tools (CUDA and cuDNN), Jetson robotics, embedded systems, and optimization for lower compute and energy use. Direction: use a VLA to take actions on a robot. One month deliverable: gather VLA literature, narrow the topic to a greenhouse, and prepare an article skeleton. Open questions: exact greenhouse task, available robot and Jetson, datasets, review date, and expected prototype depth.",
    date: "", next: "Confirm the available equipment and agree on one greenhouse task and review date."
  }
];

async function ensureWorkspace(sql) {
  await sql`CREATE TABLE IF NOT EXISTS thesis_workspace_records (
    id TEXT PRIMARY KEY,
    record JSONB NOT NULL,
    revision INTEGER NOT NULL DEFAULT 1
  )`;
}

export async function readWorkspace(sql) {
  await ensureWorkspace(sql);
  const rows = await sql`SELECT record, revision FROM thesis_workspace_records`;
  const records = new Map(starters.map(record => [record.id, { ...record, revision: 0 }]));
  for (const row of rows) records.set(row.record.id, { ...row.record, revision: row.revision });
  return [...records.values()];
}

const uuid = /^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/;
const statuses = ["todo", "doing", "done"];

export function cleanRecord(input, originalIds) {
  if (typeof input?.id !== "string" || !Number.isInteger(input.revision) || input.revision < 0 || input.revision >= 2147483647) {
    throw new Error("Invalid record.");
  }
  const { id, kind, revision } = input;
  if (typeof input.archived !== "boolean") throw new Error("Invalid archive state.");
  const record = { id, kind, archived: input.archived };
  if (kind === "archive" && originalIds.has(id) && !/^g[0-6]$/.test(id)) return { record, revision };
  const starter = starters.find(entry => entry.id === id);
  if (!["task", "journal"].includes(kind) || (starter ? starter.kind !== kind : !uuid.test(id))) {
    throw new Error("Invalid item type.");
  }
  const field = (key, limit, required = false) => {
    const value = input[key];
    if (typeof value !== "string" || value.length > limit || (required && !value.trim())) throw new Error("Check required fields and character limits.");
    return value.trim();
  };
  record.title = field("title", 160, true);
  record.detail = field("detail", 8000, kind === "journal");
  if (kind === "task") {
    if (![0, 1, 2, 3, 4].includes(input.week) || !statuses.includes(input.status)) throw new Error("Invalid week or status.");
    Object.assign(record, { week: input.week, status: input.status });
  } else {
    const date = field("date", 10);
    if (date && !/^\d{4}-\d{2}-\d{2}$/.test(date)) throw new Error("Invalid date.");
    Object.assign(record, { date, next: field("next", 1000) });
  }
  return { record, revision };
}

export async function saveWorkspaceRecord(sql, record, revision) {
  await ensureWorkspace(sql);
  const data = JSON.stringify(record);
  const rows = revision === 0
    ? await sql`INSERT INTO thesis_workspace_records (id, record) VALUES (${record.id}, ${data}::jsonb)
        ON CONFLICT (id) DO NOTHING RETURNING revision`
    : await sql`UPDATE thesis_workspace_records SET record = ${data}::jsonb, revision = revision + 1
        WHERE id = ${record.id} AND revision = ${revision} RETURNING revision`;
  return rows.length ? { ...record, revision: rows[0].revision } : null;
}
