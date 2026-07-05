import { useState } from "react";

export function label(value) {
  return String(value || "").replaceAll("_", " ").replace(/\b\w/g, (letter) => letter.toUpperCase());
}

export function roleLabel(role) {
  if (role === "super_admin") return "Geronimo / Super Admin";
  if (role === "developer_admin") return "Developer Admin";
  if (role === "pm_admin") return "Myren / PM Admin";
  if (role === "community_events_admin") return "Community Events Admin";
  if (role === "som_admin") return "Sales Operations Admin";
  return label(role || "No admin role");
}

export function useFormState(initialState) {
  const [state, setState] = useState(initialState);
  const update = (key, value) => setState((current) => ({ ...current, [key]: value }));
  const reset = () => setState(initialState);
  return [state, update, reset];
}

export function AdminCard({ eyebrow, title, children, wide = false }) {
  return <section className={wide ? "admin-card wide" : "admin-card"}>{eyebrow && <p className="eyebrow">{eyebrow}</p>}{title && <h2>{title}</h2>}{children}</section>;
}

export function Metric({ name, value, help }) {
  return <section className="ha-admin-metric"><span>{name}</span><strong>{value ?? 0}</strong>{help && <p>{help}</p>}</section>;
}

export function Guard({ final = false, lane = "admin" }) {
  return <section className="ha-admin-guard"><strong>{final ? "Final approval role active" : "Approval guardrail active"}</strong><p>{final ? "Geronimo can review and finalize protected decisions." : `This ${lane} lane can organize, draft, track, and submit requests, but cannot approve, publish, schedule, certify, or promise payment.`}</p></section>;
}

export function Tabs({ tabs, activeTab, onChange }) {
  return <nav className="admin-tabs" aria-label="Admin dashboard tabs">{tabs.map((tab) => <button key={tab.id} className={activeTab === tab.id ? "active" : ""} onClick={() => onChange(tab.id)}>{tab.label}</button>)}</nav>;
}

export function RecordList({ title, rows, primary, secondary, status, emptyText = "No records yet." }) {
  return <section className="admin-list">{title && <h3>{title}</h3>}{!rows?.length ? <p className="ha-admin-empty">{emptyText}</p> : rows.map((row) => <article key={row.id}><div><strong>{row[primary] || "Untitled"}</strong><p>{row[secondary] || "No details yet"}</p></div>{status && <span>{label(row[status] || "draft")}</span>}</article>)}</section>;
}

export function Field({ field, value, onChange }) {
  const inputValue = value ?? "";
  if (field.type === "textarea") return <label className="wide"><span>{field.label}</span><textarea value={inputValue} onChange={(event) => onChange(field.name, event.target.value)} required={field.required} /></label>;
  if (field.type === "select") return <label><span>{field.label}</span><select value={inputValue || field.options?.[0] || ""} onChange={(event) => onChange(field.name, event.target.value)} required={field.required}>{(field.options || []).map((option) => <option key={option} value={option}>{label(option)}</option>)}</select></label>;
  if (field.type === "checkbox") return <label className="admin-checkbox-field"><input type="checkbox" checked={Boolean(value)} onChange={(event) => onChange(field.name, event.target.checked)} /><span>{field.label}</span></label>;
  return <label><span>{field.label}</span><input type={field.type || "text"} value={inputValue} onChange={(event) => onChange(field.name, event.target.value)} required={field.required} /></label>;
}

export function RecordForm({ fields, form, update, onSubmit, buttonLabel = "Save" }) {
  return <form className="admin-form" onSubmit={(event) => { event.preventDefault(); onSubmit(); }}>{fields.map((field) => <Field key={field.name} field={field} value={form[field.name]} onChange={update} />)}<button type="submit">{buttonLabel}</button></form>;
}
