export interface NotificationMessage {
  title: string;
  body: string;
  priority?: "low" | "default" | "high" | "urgent";
  url?: string;
}

export async function send(message: NotificationMessage): Promise<void> {
  void message;
  throw new Error("Provider fcm is a placeholder.");
}
