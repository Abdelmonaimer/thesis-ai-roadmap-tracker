(() => {
  const byId = id => document.getElementById(id);
  const workspace = byId("research-workspace");
  const form = byId("research-form");
  const editor = byId("research-editor");
  const feedback = byId("research-status");
  const draftFeedback = byId("research-draft-status");
  const statusLabels = { todo: "Not started", doing: "In progress", done: "Finished" };
  const weeks = ["Backlog", "Week 1 · Foundations and scope", "Week 2 · Literature and method", "Week 3 · Embedded baseline", "Week 4 · Article outline"];
  const templates = {
    paper: "Citation or link:\nProblem and task:\nInputs and actions:\nDataset and hardware:\nMetrics and findings:\nLimitation and relevance to my study:",
    experiment: "Question and hypothesis:\nCode, data, and model version:\nHardware and power mode:\nProcedure and success criterion:\nTrials, latency, memory and energy:\nResult or blocker:",
    review: "What I finished:\nWhat I learned or decided:\nBlockers and questions for supervisors:\nThree priorities for next week:"
  };
  const records = new Map();
  let draft = null;
  let ready = false;
  let busy = false;
  let session = 0;

  function setControls() {
    workspace.querySelectorAll("[data-ws]").forEach(button => {
      button.disabled = busy || (!ready && button.dataset.ws !== "reload" && button.dataset.ws !== "cancel");
    });
    document.querySelectorAll(".original-archive").forEach(button => { button.disabled = busy || !ready; });
    form.querySelector('button[type="submit"]').disabled = busy;
  }

  function button(action, label, id = "") {
    return `<button type="button" class="quiet-button" data-ws="${action}" data-record="${esc(id)}">${label}</button>`;
  }

  function card(record) {
    const title = record.kind === "archive" ? TASK_BY_ID.get(record.id)?.title : record.title;
    const meta = record.kind === "journal" ? (record.date || "Undated") : statusLabels[record.status] || "";
    const detail = record.detail ? `<p>${esc(record.detail)}</p>` : "";
    const next = record.next ? `<p><strong>Next step</strong> · ${esc(record.next)}</p>` : "";
    const actions = record.archived
      ? button("restore", "Restore", record.id)
      : button("edit", "Edit", record.id) + button("archive", "Archive", record.id);
    return `<article class="research-record"><strong>${esc(title || record.id)}</strong>
      ${meta ? `<div><small>${esc(meta)}</small></div>` : ""}${detail}${next}
      <div class="research-actions">${actions}</div></article>`;
  }

  function renderWorkspace() {
    const active = [...records.values()].filter(record => !record.archived);
    const tasks = active.filter(record => record.kind === "task");
    const entries = active.filter(record => record.kind === "journal");
    const archived = [...records.values()].filter(record => record.archived);
    byId("research-task-list").innerHTML = `<div class="research-grid">${[1, 2, 3, 4, 0].map(week => {
      const group = tasks.filter(task => task.week === week);
      const finished = group.filter(task => task.status === "done").length;
      return `<section class="research-week"><h4>${weeks[week]}</h4>
        <small>${finished} of ${group.length} finished</small>
        ${group.map(card).join("") || "<p>No tasks here yet.</p>"}</section>`;
    }).join("")}</div>`;
    byId("research-journal-list").innerHTML = entries.sort((a, b) => b.date.localeCompare(a.date)).map(card).join("") || "<p>No entries yet.</p>";
    byId("research-archive-list").innerHTML = archived.map(card).join("") || "<p>No archived items.</p>";
    for (const task of TASKS) {
      if (task.gate) continue;
      const hidden = Boolean(records.get(task.id)?.archived);
      byId("it-" + task.id)?.classList.toggle("roadmap-archived", hidden);
      document.querySelector(`.mchip[data-go="${task.id}"]`)?.classList.toggle("roadmap-archived", hidden);
    }
    apply();
    setControls();
  }

  async function loadWorkspace() {
    if (busy || !authenticated) return;
    const currentSession = session;
    busy = true;
    setControls();
    feedback.textContent = "Loading research records…";
    try {
      const data = await api("/api/progress?view=workspace");
      if (currentSession !== session) return;
      records.clear();
      for (const record of data.records) records.set(record.id, record);
      ready = true;
      renderWorkspace();
      feedback.textContent = "Research records loaded from Neon.";
    } catch (error) {
      if (currentSession === session) feedback.textContent = error.message;
    } finally {
      if (currentSession === session) {
        busy = false;
        setControls();
      }
    }
  }

  function closeEditor() {
    draft = null;
    editor.open = false;
    editor.hidden = true;
    form.reset();
    draftFeedback.textContent = "";
  }

  function openEditor(kind, existing, template) {
    if (draft) {
      draftFeedback.textContent = "Save or cancel this draft before opening another.";
      editor.scrollIntoView({ block: "nearest" });
      return;
    }
    const today = new Date();
    const localDate = new Date(today.getTime() - today.getTimezoneOffset() * 60000).toISOString().slice(0, 10);
    draft = existing || {
      id: crypto.randomUUID(), revision: 0, kind, archived: false,
      title: "", week: 0, status: "todo", date: localDate, detail: templates[template] || "", next: ""
    };
    const isTask = kind === "task";
    byId(isTask ? "research-tasks" : "research-journal").prepend(editor);
    byId("research-task-fields").hidden = !isTask;
    byId("research-date").hidden = isTask;
    byId("research-next").hidden = isTask;
    byId("research-detail-title").textContent = isTask ? "Details" : "Work and findings";
    form.elements.detail.required = !isTask;
    for (const name of ["title", "week", "status", "date", "detail", "next"]) {
      if (draft[name] !== undefined) form.elements[name].value = draft[name];
    }
    byId("research-editor-title").textContent = existing ? "Edit " + (isTask ? "task" : "journal entry") : "New " + (isTask ? "task" : "journal entry");
    editor.hidden = false;
    editor.open = true;
    form.querySelector('[data-ws="rebase"]').hidden = true;
    form.elements.title.focus();
  }

  async function save(record, editing = false) {
    if (busy || !ready) return;
    const currentSession = session;
    busy = true;
    setControls();
    const message = editing ? draftFeedback : byId("research-action-status");
    message.textContent = "Saving to Neon…";
    try {
      const data = await api("/api/progress", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action: "saveWorkspace", record })
      });
      if (currentSession !== session) return;
      records.set(data.record.id, data.record);
      if (editing) closeEditor();
      message.textContent = "";
      byId("research-action-status").textContent = "Saved to Neon.";
      renderWorkspace();
    } catch (error) {
      if (currentSession !== session) return;
      message.textContent = error.message;
      if (error.status === 409) {
        busy = false;
        await loadWorkspace();
        if (editing && currentSession === session) form.querySelector('[data-ws="rebase"]').hidden = false;
      }
    } finally {
      if (currentSession === session) {
        busy = false;
        setControls();
      }
    }
  }

  form.addEventListener("submit", event => {
    event.preventDefault();
    if (!draft) return;
    const fields = new FormData(form);
    const record = { ...draft, archived: false, title: fields.get("title"), detail: fields.get("detail") };
    if (draft.kind === "task") Object.assign(record, { week: Number(fields.get("week")), status: fields.get("status") });
    else Object.assign(record, { date: fields.get("date"), next: fields.get("next") });
    save(record, true);
  });

  document.addEventListener("click", event => {
    if (event.target.closest('a[href="#research-resources"]')) byId("research-resources").open = true;
    const control = event.target.closest("[data-ws]");
    if (!control || !authenticated) return;
    const action = control.dataset.ws;
    const id = control.dataset.record;
    const record = records.get(id);
    if (action === "reload") loadWorkspace();
    if (action === "cancel") closeEditor();
    if (action === "task") openEditor("task");
    if (["journal", "paper", "experiment", "review"].includes(action)) openEditor("journal", null, action);
    if (action === "edit" && record) openEditor(record.kind, record);
    if (action === "archive") {
      if (draft?.id === id) {
        draftFeedback.textContent = "Save or cancel the open draft before archiving this item.";
        editor.scrollIntoView({ block: "nearest" });
        return;
      }
      if (!record && !TASK_BY_ID.has(id)) return;
      const archived = record || { id, kind: "archive", revision: 0 };
      save({ ...archived, archived: true });
    }
    if (action === "restore" && record) save({ ...record, archived: false });
    if (action === "rebase" && draft && records.has(draft.id)) {
      draft = { ...draft, revision: records.get(draft.id).revision };
      control.hidden = true;
      draftFeedback.textContent = "Draft kept. Press Save to apply it to the latest version.";
    }
    if (action === "download") {
      const blob = new Blob([JSON.stringify([...records.values()], null, 2)], { type: "application/json" });
      const url = URL.createObjectURL(blob);
      const link = document.createElement("a");
      link.href = url;
      link.download = "thesis-research-records.json";
      link.click();
      setTimeout(() => URL.revokeObjectURL(url), 1000);
    }
  });

  function updateSession() {
    session++;
    busy = false;
    ready = false;
    records.clear();
    closeEditor();
    feedback.textContent = "";
    byId("research-action-status").textContent = "";
    if (authenticated) loadWorkspace();
    else renderWorkspace();
  }

  document.addEventListener("roadmap-session", updateSession);
  updateSession();
})();
