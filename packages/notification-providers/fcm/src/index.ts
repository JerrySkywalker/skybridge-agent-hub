export interface NotificationMessage {
  title: string;
  body: string;
  priority?: "low" | "default" | "high" | "urgent";
  url?: string;
}

export interface NotificationProviderResult {
  provider: "fcm";
  status: "sent" | "skipped" | "failed";
  error?: string;
}

export async function send(message: NotificationMessage): Promise<NotificationProviderResult> {
  void message;
  return { provider: "fcm", status: "skipped", error: "FCM_SERVER_KEY is not configured." };
}
