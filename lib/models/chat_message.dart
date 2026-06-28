enum ChatSender { user, assistant }

class ChatMessage {
  final ChatSender sender;
  final String text;
  const ChatMessage(this.sender, this.text);
}
