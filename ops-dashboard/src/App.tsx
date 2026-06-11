import { NavLink, Route, Routes } from "react-router-dom";
import MonitoringPage from "@/pages/MonitoringPage";
import AlertsPage from "@/pages/AlertsPage";
import DocumentationPage from "@/pages/DocumentationPage";
import ApiTestPage from "@/pages/ApiTestPage";
import RoutingConfigPage from "@/pages/RoutingConfigPage";

const links: { to: string; label: string; end?: boolean }[] = [
  { to: "/", label: "Monitoramento", end: true },
  { to: "/alertas", label: "Alertas" },
  { to: "/documentacao", label: "Documentação" },
  { to: "/api-teste", label: "API teste" },
  { to: "/roteamento", label: "Config roteamento" },
];

export default function App() {
  return (
    <div className="ops-shell">
      <nav className="ops-nav">
        {links.map((l) => (
          <NavLink
            key={l.to}
            to={l.to}
            end={l.end}
            className={({ isActive }) => (isActive ? "active" : undefined)}
          >
            {l.label}
          </NavLink>
        ))}
      </nav>
      <Routes>
        <Route path="/" element={<MonitoringPage />} />
        <Route path="/alertas" element={<AlertsPage />} />
        <Route path="/documentacao" element={<DocumentationPage />} />
        <Route path="/api-teste" element={<ApiTestPage />} />
        <Route path="/roteamento" element={<RoutingConfigPage />} />
      </Routes>
    </div>
  );
}
