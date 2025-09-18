library(shiny)
library(bslib)
library(jsonlite)

ui <- page_sidebar(
  title = "Offline Data Collection",
  sidebar = sidebar(
    h4("Data Collection Form"),
    textInput("participant_id", "Participant ID", placeholder = "Enter ID"),
    selectInput("location", "Location",
                choices = c("", "Site A", "Site B", "Site C", "Other"), selected = ""
    ),
    numericInput("measurement", "Measurement Value", value = NULL, min = 0),
    textAreaInput("notes", "Notes", placeholder = "Optional notes", rows = 3),
    br(),
    actionButton("save_record", "Save Record", class = "btn-primary", width = "100%"),
    hr(),
    h5("Connection Status"),
    div(
      id = "connection_status",
      style = "padding: 10px; border-radius: 5px; margin: 10px 0;",
      "🟡 Detecting..."
    ),
    br(),
    actionButton("sync_data", "Sync to Server", class = "btn-success", width = "100%"),
    actionButton("export_data", "Export as JSON", class = "btn-info", width = "100%"),
    actionButton("clear_local", "Clear Local Data", class = "btn-warning", width = "100%")
  ),
  card(
    card_header("Stored Records"),
    div(id = "records_display"),
    hr(),
    h5("Local Storage Summary"),
    verbatimTextOutput("storage_summary")
  ),
  # --- JS for offline/local-first behavior (works in Shinylive) ---
  tags$script(HTML("
    // ---------- CONFIG ----------
    const DATA_KEY = 'shinylive_offline_data_collection';
    const SYNC_URL = '/api/collect'; // <- replace with your endpoint when you have one

    // ---------- STORAGE ----------
    function initStorage() {
      if (!localStorage.getItem(DATA_KEY)) {
        localStorage.setItem(DATA_KEY, JSON.stringify([]));
      }
    }
    function getAllRecords() {
      return JSON.parse(localStorage.getItem(DATA_KEY) || '[]');
    }
    function saveRecord(record) {
      let data = getAllRecords();
      record.id = Date.now().toString() + '_' + Math.random().toString(36).substr(2, 9);
      record.timestamp = new Date().toISOString();
      record.synced = false;
      data.push(record);
      localStorage.setItem(DATA_KEY, JSON.stringify(data));
      updateDisplay(); updateShinyStorageSummary();
      return record.id;
    }
    function markSynced(ids) {
      let data = getAllRecords();
      data.forEach(r => { if (ids.includes(r.id)) { r.synced = true; r.sync_timestamp = new Date().toISOString(); }});
      localStorage.setItem(DATA_KEY, JSON.stringify(data));
      updateDisplay(); updateShinyStorageSummary();
    }
    function clearLocalData() {
      localStorage.removeItem(DATA_KEY);
      initStorage(); updateDisplay(); updateShinyStorageSummary();
    }

    // ---------- EXPORT ----------
    function exportData() {
      const records = getAllRecords();
      if (records.length === 0) { alert('No data to export!'); return; }
      const payload = { export_timestamp: new Date().toISOString(), total_records: records.length, records };
      const blob = new Blob([JSON.stringify(payload, null, 2)], {type:'application/json'});
      const url = URL.createObjectURL(blob);
      const a = document.createElement('a');
      a.href = url;
      a.download = 'offline_data_' + new Date().toISOString().split('T')[0] + '.json';
      document.body.appendChild(a); a.click(); document.body.removeChild(a);
      URL.revokeObjectURL(url);
      alert('Data exported successfully!');
    }

    // ---------- UI ----------
    function updateShinyStorageSummary() {
      const recs = getAllRecords(); const total = recs.length;
      const synced = recs.filter(r => r.synced).length; const pending = total - synced;
      if (typeof Shiny !== 'undefined' && Shiny.setInputValue) {
        Shiny.setInputValue('storage_counts', { total, synced, pending, timestamp: Date.now() });
      }
    }
    function updateDisplay() {
      const records = getAllRecords().sort((a,b) => new Date(b.timestamp) - new Date(a.timestamp));
      const display = document.getElementById('records_display');
      if (!display) return;
      if (records.length === 0) { display.innerHTML = '<p class=\"text-muted\">No records stored locally.</p>'; return; }
      let html = '<div class=\"row\">';
      records.slice(0, 10).forEach(record => {
        const badge = record.synced ? '<span class=\"badge bg-success\">Synced</span>'
                                    : '<span class=\"badge bg-warning text-dark\">Pending</span>';
        html += `
          <div class=\"col-md-6 mb-3\">
            <div class=\"card border-0 shadow-sm\">
              <div class=\"card-body\">
                <h6 class=\"card-title d-flex justify-content-between align-items-center\">
                  ID: ${record.participant_id} ${badge}
                </h6>
                <p class=\"card-text small\">
                  <strong>Location:</strong> ${record.location}<br>
                  <strong>Measurement:</strong> ${record.measurement}<br>
                  <strong>Time:</strong> ${new Date(record.timestamp).toLocaleString()}
                </p>
                ${record.notes ? `<p class=\"card-text small\"><strong>Notes:</strong> ${record.notes}</p>` : ''}
              </div>
            </div>
          </div>`;
      });
      if (records.length > 10) {
        html += `<div class=\"col-12\"><p class=\"text-muted text-center\">Showing latest 10 of ${records.length} records</p></div>`;
      }
      html += '</div>';
      display.innerHTML = html;
    }

    // ---------- ONLINE / OFFLINE UX ----------
    function setStatus(online) {
      const el = document.getElementById('connection_status'); if (!el) return;
      if (online) { el.innerHTML = '🟢 Online (data persists in browser)'; el.style.backgroundColor = '#d4edda'; el.style.color = '#155724'; }
      else        { el.innerHTML = '🔴 Offline (safe to collect; will sync later)'; el.style.backgroundColor = '#f8d7da'; el.style.color = '#721c24'; }
    }

    // ---------- SYNC ----------
    async function syncToServerReal() {
      const unsynced = getAllRecords().filter(r => !r.synced);
      if (unsynced.length === 0) { alert('No records to sync!'); return; }
      const btn = document.querySelector('#sync_data'); const orig = btn.innerHTML;
      try {
        btn.innerHTML = 'Syncing...'; btn.disabled = true;
        // NOTE: replace SYNC_URL with a real endpoint. Example payload below:
        const resp = await fetch(SYNC_URL, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ device_timestamp: new Date().toISOString(), records: unsynced })
        });
        if (!resp.ok) throw new Error('HTTP ' + resp.status);
        // Expect server to return the list of accepted record IDs, or echo back records
        const result = await resp.json();
        const ids = result.ids || unsynced.map(r => r.id); // fallback: mark all
        markSynced(ids);
        alert(`Successfully synced ${ids.length} records!`);
      } catch (e) {
        alert('Sync failed: ' + e.message + '\\nData remains safely stored locally.');
      } finally {
        btn.innerHTML = orig; btn.disabled = false;
      }
    }

    // Default: if no server yet, simulate success so field teams can test UX
    async function syncToServerSim() {
      const unsynced = getAllRecords().filter(r => !r.synced);
      if (unsynced.length === 0) { alert('No records to sync!'); return; }
      const btn = document.querySelector('#sync_data'); const orig = btn.innerHTML;
      try {
        btn.innerHTML = 'Syncing...'; btn.disabled = true;
        await new Promise(r => setTimeout(r, 1200));
        const ids = unsynced.map(r => r.id);
        markSynced(ids);
        alert(`Successfully synced ${ids.length} records! (Simulated)`);
      } finally {
        btn.innerHTML = orig; btn.disabled = false;
      }
    }

    // Use real sync if SYNC_URL set; otherwise simulate
    function syncToServer() {
      if (SYNC_URL && SYNC_URL !== '/api/collect') return syncToServerReal();
      return syncToServerSim();
    }

    // ---------- INIT + EVENTS ----------
    function initializeApp() {
      initStorage(); updateDisplay(); updateShinyStorageSummary();
      setStatus(navigator.onLine);
      window.addEventListener('online',  () => setStatus(true));
      window.addEventListener('offline', () => setStatus(false));
      // Optional: Background Sync (if SW registers 'sync'); otherwise manual button
      if ('serviceWorker' in navigator) {
        navigator.serviceWorker.ready.then(reg => {
          if ('sync' in reg) {
            // Example: queue name 'offline-sync'; you could trigger reg.sync.register('offline-sync')
          }
        });
      }
    }
    $(document).ready(() => setTimeout(initializeApp, 300));

    $(document).on('click', '#save_record', function() {
      const id = document.getElementById('participant_id').value.trim();
      const loc = document.getElementById('location').value;
      const meas = document.getElementById('measurement').value;
      const notes = document.getElementById('notes').value;
      if (!id || !loc || !meas) { alert('Please fill in all required fields (ID, Location, Measurement)'); return; }
      saveRecord({ participant_id: id, location: loc, measurement: parseFloat(meas), notes });
      document.getElementById('participant_id').value = '';
      document.getElementById('location').value = '';
      document.getElementById('measurement').value = '';
      document.getElementById('notes').value = '';
      alert('Record saved locally! Total records: ' + getAllRecords().length);
    });
    $(document).on('click', '#sync_data',   () => syncToServer());
    $(document).on('click', '#export_data', () => exportData());
    $(document).on('click', '#clear_local', () => {
      if (confirm('Are you sure you want to clear all local data? This cannot be undone!')) {
        clearLocalData(); alert('Local data cleared!');
      }
    });
  "))
)

server <- function(input, output, session) {
  storage_data <- reactiveVal(list(total = 0, synced = 0, pending = 0))
  observeEvent(input$storage_counts, {
    if (!is.null(input$storage_counts)) {
      storage_data(list(
        total   = input$storage_counts$total   %||% 0,
        synced  = input$storage_counts$synced  %||% 0,
        pending = input$storage_counts$pending %||% 0
      ))
    }
  }, ignoreInit = FALSE)
  output$storage_summary <- renderText({
    d <- storage_data()
    paste0(
      'Total Records: ', d$total, '\n',
      'Synced: ', d$synced, '\n',
      'Pending Sync: ', d$pending, '\n',
      'Storage: Browser Local Storage\n',
      'Platform: Shinylive (webR)\n',
      'Last Updated: ', format(Sys.time(), '%H:%M:%S')
    )
  })
  `%||%` <- function(x, y) if (is.null(x)) y else x
}

shinyApp(ui, server)