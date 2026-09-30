async function buscarDados() {
  const resp = await fetch("/api/dados");
  const dados = await resp.json();
  if (!dados.length) return;

  const ultimo = dados[dados.length - 1];
  document.getElementById("ultima-atualizacao").innerText = "Atualizado: " + ultimo.timestamp;

  // Cards de status geral
  const disco = ultimo.discos.find(d => d.particao === "/") || { uso_percent: 0 };

  const cards = document.getElementById("cards-status");
  cards.innerHTML = `
    <div class="card ${ultimo.ram.uso_percent >= 85 ? 'alerta' : 'ok'}">RAM: ${ultimo.ram.uso_percent}%</div>
    <div class="card ${ultimo.cpu_percent >= 90 ? 'alerta' : 'ok'}">CPU: ${ultimo.cpu_percent}%</div>
    <div class="card ${disco.uso_percent >= 85 ? 'alerta' : 'ok'}">Disco: ${disco.uso_percent}%</div>
    <div class="card ok">Conexões TCP: ${ultimo.conexoes_tcp}</div>
    <div class="card ok">Uptime: ${Math.floor(ultimo.uptime_segundos/3600)}h</div>
  `;


  // Tabela de serviços
  const tbody = document.querySelector("#tabela-servicos tbody");
  tbody.innerHTML = "";
  ultimo.servicos.forEach(s => {
    const classe = s.status === "ativo" ? "status-ativo" : "status-parado";
    tbody.innerHTML += `<tr><td>${s.nome}</td><td>${s.servico}</td><td class="${classe}">${s.status}</td></tr>`;
  });

  // Tabela de containers - Proxy
  const tbodyProxy = document.querySelector("#tabela-containers-proxy tbody");
  tbodyProxy.innerHTML = "";
  ultimo.containers_proxy.forEach(c => {
    const classe = c.status === "ativo" ? "status-ativo" : "status-parado";
    tbodyProxy.innerHTML += `<tr><td>${c.nome}</td><td>${c.container}</td><td class="${classe}">${c.status}</td></tr>`;
  });

  // Tabela de containers - Bancos de Dados
  const tbodyDb = document.querySelector("#tabela-containers-db tbody");
  tbodyDb.innerHTML = "";
  ultimo.containers_db.forEach(c => {
    const classe = c.status === "ativo" ? "status-ativo" : "status-parado";
    tbodyDb.innerHTML += `<tr><td>${c.nome}</td><td>${c.container}</td><td class="${classe}">${c.status}</td><td>${c.tamanho_mb}</td></tr>`;
  });

  // Alertas
  const listaAlertas = document.getElementById("lista-alertas");
  listaAlertas.innerHTML = "";
  if (ultimo.alertas.length === 0) {
    listaAlertas.innerHTML = "<li style='background:#166534;'>Nenhum alerta ativo</li>";
  } else {
    ultimo.alertas.forEach(a => listaAlertas.innerHTML += `<li>${a}</li>`);
  }

  // Gráficos
  const labels = dados.map(d => d.timestamp.split(" ")[1]);
  renderGrafico("graficoRam", labels, dados.map(d => d.ram.uso_percent), "RAM %", "#3b82f6");
  renderGrafico("graficoCpu", labels, dados.map(d => d.cpu_percent), "CPU %", "#f59e0b");
  renderGraficoRede(labels, dados.map(d => d.rede.rx_kbps), dados.map(d => d.rede.tx_kbps));
}

let charts = {};
function renderGrafico(id, labels, dados, label, cor) {
  if (charts[id]) charts[id].destroy();
  charts[id] = new Chart(document.getElementById(id), {
    type: "line",
    data: { labels, datasets: [{ label, data: dados, borderColor: cor, tension: 0.3 }] },
    options: { responsive: true, scales: { y: { beginAtZero: true } } }
  });
}

function renderGraficoRede(labels, rx, tx) {
  if (charts["rede"]) charts["rede"].destroy();
  charts["rede"] = new Chart(document.getElementById("graficoRede"), {
    type: "line",
    data: {
      labels,
      datasets: [
        { label: "Download (KB/s)", data: rx, borderColor: "#22c55e", tension: 0.3 },
        { label: "Upload (KB/s)", data: tx, borderColor: "#ef4444", tension: 0.3 }
      ]
    },
    options: { responsive: true, scales: { y: { beginAtZero: true } } }
  });
}

buscarDados();
setInterval(buscarDados, 15000); // Atualiza a cada 15s
