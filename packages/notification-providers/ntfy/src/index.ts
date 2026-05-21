export interface NotificationMessage {
  title: string;
  body: string;
  priority?: "low" | "default" | "high" | "urgent";
  url?: string;
}

export interface NotificationProviderResult {
  provider: "ntfy";
  status: "sent" | "skipped" | "failed";
  error?: string;
}

export interface NtfyConfig {
  topicUrl: string;
  token?: string;
}

export async function send(message: NotificationMessage, config?: Partial<NtfyConfig>): Promise<NotificationProviderResult> {
  const topicUrl = config?.topicUrl ?? process.env.NTFY_TOPIC_URL;
  if (!topicUrl) {
    return { provider: "ntfy", status: "skipped", error: "NTFY_TOPIC_URL is not configured." };
  }

  const headers: Record<string, string> = {
    "content-type": "text/plain; charset=utf-8",
    title: message.title,
    priority: message.priority ?? "default"
  };
  const token = config?.token ?? process.env.NTFY_TOKEN;
  if (token) headers.authorization = `Bearer ${token}`;
  if (message.url) headers.click = message.url;

  const response = await fetch(topicUrl, {
    method: "POST",
    headers,
    body: message.body
  });

  if (!response.ok) {
    return { provider: "ntfy", status: "failed", error: `ntfy request failed with HTTP ${response.status}` };
  }

  return { provider: "ntfy", status: "sent" };
}
