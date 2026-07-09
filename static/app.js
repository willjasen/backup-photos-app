const state = {
  lists: { albums: "", people: "" },
  activeEditor: "albums",
  lastLogLine: -1,
  polling: false,
};

const elements = {
  editor: document.querySelector("#list-editor"),
  tabs: [...document.querySelectorAll(".tab")],
  saveButton: document.querySelector("#save-button"),
  saveMessage: document.querySelector("#save-message"),
  startButton: document.querySelector("#start-button"),
  stopButton: document.querySelector("#stop-button"),
  exportMessage: document.querySelector("#export-message"),
  log: document.querySelector("#log-output"),
  statusPill: document.querySelector("#status-pill"),
  statusLabel: document.querySelector("#status-label"),
  runTime: document.querySelector("#run-time"),
};

async function api(path, options = {}) {
  const response = await fetch(path, {
    ...options,
    headers: {
      "Content-Type": "application/json",
      ...(options.headers || {}),
    },
  });
  const body = await response.json();
  if (!response.ok) {
    throw new Error(body.error || `Request failed (${response.status})`);
  }
  return body;
}

function setMessage(element, text, type = "") {
  element.textContent = text;
  element.className = `message ${type}`.trim();
}

function formatCount(count, noun) {
  return `${count} ${noun}${count === 1 ? "" : "s"}`;
}

function storeCurrentEditor() {
  state.lists[state.activeEditor] = elements.editor.value;
}

function showEditor(name) {
  storeCurrentEditor();
  state.activeEditor = name;
  elements.editor.value = state.lists[name];
  elements.tabs.forEach((tab) => {
    const active = tab.dataset.editor === name;
    tab.classList.toggle("active", active);
    tab.setAttribute("aria-selected", String(active));
  });
  elements.editor.focus();
}

async function loadOverview() {
  try {
    const overview = await api("/api/overview");
    document.querySelector("#library-note").textContent =
      overview.photos_library || "Photos library is not configured";
    const dateInput = document.querySelector('input[value="date"]');
    const dateOption = document.querySelector("#date-option");
    if (overview.date_range.available) {
      document.querySelector("#date-range").textContent =
        `${overview.date_range.from} → ${overview.date_range.to}`;
    } else {
      dateInput.disabled = true;
      dateOption.classList.add("disabled");
      document.querySelector("#date-range").textContent = "Add dates in config.json";
    }
  } catch (error) {
    setMessage(elements.exportMessage, error.message, "error");
  }
}

async function loadLists() {
  try {
    const result = await api("/api/lists");
    state.lists = result.contents;
    elements.editor.value = state.lists[state.activeEditor];
    document.querySelector("#album-count").textContent =
      formatCount(result.counts.albums, "album");
    document.querySelector("#people-count").textContent =
      `${result.counts.people} ${result.counts.people === 1 ? "person" : "people"}`;
    document.querySelector("#list-directory").textContent = result.directory;
  } catch (error) {
    setMessage(elements.saveMessage, error.message, "error");
    elements.editor.disabled = true;
    elements.saveButton.disabled = true;
  }
}

async function saveLists() {
  storeCurrentEditor();
  elements.saveButton.disabled = true;
  setMessage(elements.saveMessage, "Saving…");
  try {
    const result = await api("/api/lists", {
      method: "PUT",
      body: JSON.stringify({ contents: state.lists }),
    });
    state.lists = result.contents;
    document.querySelector("#album-count").textContent =
      formatCount(result.counts.albums, "album");
    document.querySelector("#people-count").textContent =
      `${result.counts.people} ${result.counts.people === 1 ? "person" : "people"}`;
    setMessage(elements.saveMessage, "Saved.", "success");
  } catch (error) {
    setMessage(elements.saveMessage, error.message, "error");
  } finally {
    elements.saveButton.disabled = false;
  }
}

function selectedModes() {
  return [...document.querySelectorAll('input[name="mode"]:checked')]
    .map((input) => input.value);
}

function logLineClass(text) {
  const normalized = text.toLowerCase();
  if (
    normalized.includes("error") ||
    normalized.includes("failed") ||
    normalized.includes("not found") ||
    normalized.includes("exit code")
  ) {
    return "log-error";
  }
  if (
    normalized.includes("warning") ||
    normalized.includes("unable to") ||
    normalized.includes("stopping") ||
    normalized.includes("interrupt")
  ) {
    return "log-warning";
  }
  if (
    normalized.includes("finished") ||
    normalized.includes("completed") ||
    normalized.includes("successfully")
  ) {
    return "log-success";
  }
  if (
    normalized.startsWith("starting export:") ||
    normalized.startsWith("running ")
  ) {
    return "log-heading";
  }
  if (
    normalized.startsWith("processing ") ||
    normalized.startsWith("progress:")
  ) {
    return "log-progress";
  }
  return "";
}

function appendLogLine(text) {
  const line = document.createElement("span");
  line.className = `log-line ${logLineClass(text)}`.trim();
  line.textContent = text || " ";
  elements.log.append(line, "\n");
}

async function startExport() {
  const modes = selectedModes();
  if (!modes.length) {
    setMessage(elements.exportMessage, "Choose at least one export type.", "error");
    return;
  }
  elements.startButton.disabled = true;
  setMessage(elements.exportMessage, "Starting…");
  try {
    state.lastLogLine = -1;
    elements.log.textContent = "";
    await api("/api/export/start", {
      method: "POST",
      body: JSON.stringify({ modes }),
    });
    setMessage(elements.exportMessage, "Export started.", "success");
    await pollStatus();
  } catch (error) {
    setMessage(elements.exportMessage, error.message, "error");
    elements.startButton.disabled = false;
  }
}

async function stopExport() {
  elements.stopButton.disabled = true;
  setMessage(elements.exportMessage, "Stopping…");
  try {
    await api("/api/export/stop", { method: "POST", body: "{}" });
  } catch (error) {
    setMessage(elements.exportMessage, error.message, "error");
  }
}

function updateStatus(status) {
  elements.statusPill.classList.remove("running", "success", "failed");
  elements.startButton.disabled = status.running;
  elements.stopButton.disabled = !status.running;

  if (status.running) {
    elements.statusPill.classList.add("running");
    elements.statusLabel.textContent = "Exporting";
    elements.runTime.textContent = `Started ${new Date(status.started_at).toLocaleString()}`;
  } else if (status.exit_code === 0) {
    elements.statusPill.classList.add("success");
    elements.statusLabel.textContent = "Complete";
    elements.runTime.textContent = `Finished ${new Date(status.finished_at).toLocaleString()}`;
    setMessage(elements.exportMessage, "Export completed.", "success");
  } else if (status.exit_code !== null) {
    elements.statusPill.classList.add("failed");
    elements.statusLabel.textContent = "Stopped";
    elements.runTime.textContent = `Stopped ${new Date(status.finished_at).toLocaleString()}`;
    setMessage(elements.exportMessage, "Export stopped.", "error");
  } else {
    elements.statusLabel.textContent = "Ready";
  }

  if (status.lines.length) {
    if (state.lastLogLine < 0) {
      elements.log.textContent = "";
    }
    for (const line of status.lines) {
      appendLogLine(line.text);
    }
    state.lastLogLine = status.next_after;
    elements.log.scrollTop = elements.log.scrollHeight;
  }
}

async function pollStatus() {
  if (state.polling) return;
  state.polling = true;
  try {
    const status = await api(`/api/export/status?after=${state.lastLogLine}`);
    updateStatus(status);
  } catch (error) {
    setMessage(elements.exportMessage, error.message, "error");
  } finally {
    state.polling = false;
  }
}

elements.tabs.forEach((tab) => {
  tab.addEventListener("click", () => showEditor(tab.dataset.editor));
});
elements.saveButton.addEventListener("click", saveLists);
elements.startButton.addEventListener("click", startExport);
elements.stopButton.addEventListener("click", stopExport);

loadOverview();
loadLists();
pollStatus();
setInterval(pollStatus, 1000);
