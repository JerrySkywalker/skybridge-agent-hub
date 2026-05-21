export interface NotificationMessage {
  title: string;
  body: string;
  priority?: "low" | "default" | "high" | "urgent";
  url?: string;
}

export interface NotificationProviderResult {
  provider: "apprise";
  status: "sent" | "skipped" | "failed";
  error?: string;
}

export async function send(message: NotificationMessage): Promise<NotificationProviderResult> {
  void message;
  return { provider: "apprise", status: "skipped", error: "APPRISE_URL is not configured." };
}
