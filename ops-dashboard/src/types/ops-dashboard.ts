export type DeploymentEnvironment = {
  id: string;
  environment_name: string;
  display_name?: string | null;
};

export type UsageMetric = {
  id: string;
  metric_name: string;
  metric_value: number;
  metric_unit: string | null;
  environment?: string;
  source?: string | null;
  recorded_at: string;
};

export type HealthCheck = {
  id: string;
  check_name: string;
  status: string;
  response_ms: number | null;
  details: Record<string, unknown> | null;
  checked_at: string;
  deployment_environments?: DeploymentEnvironment | null;
};

export type NotificationRow = {
  id: string;
  title: string;
  message: string | null;
  severity: string;
  is_read: boolean;
  source?: string | null;
  created_at: string;
};

export type DocumentationRow = {
  id: string;
  title: string;
  slug: string | null;
  body: string | null;
  doc_type: string | null;
  tags: string[] | null;
  language: string;
  is_published: boolean;
  updated_at: string;
};

export type TruckRoutingConfigRow = {
  id: string;
  config_key: string;
  config_value: Record<string, unknown>;
  environment: string;
  description: string | null;
  updated_at: string;
};

export type HealthCheckInvokeResult = {
  status: "ok" | "degraded" | "error";
  source?: string;
  environment?: string;
  checks?: Record<string, unknown>;
  elapsed_ms?: number;
  message?: string;
};
