export interface NotificationMessage {
  title: string;
  body: string;
  priority?: "low" | "default" | "high" | "urgent";
  url?: string;
}

export interface NotificationProviderResult {
  provider: "wecom";
  status: "sent" | "skipped" | "failed";
  error?: string;
}

export async function send(message: NotificationMessage): Promise<NotificationProviderResult> {
  void message;
  return { provider: "wecom", status: "skipped", error: "WECOM_WEBHOOK_URL is not configured." };
}
