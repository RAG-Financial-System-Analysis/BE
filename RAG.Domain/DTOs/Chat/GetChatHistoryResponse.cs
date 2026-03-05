using System;
using System.Collections.Generic;

namespace RAG.Domain.DTOs.Chat
{
    public class MessageDto
    {
        public Guid Id { get; set; }
        public string QuestionText { get; set; } = string.Empty;
        public string ResponseText { get; set; } = string.Empty;
        public DateTime CreatedAt { get; set; }
    }

    public class GetChatHistoryResponse
    {
        public Guid SessionId { get; set; }
        public List<MessageDto> Messages { get; set; } = new();
    }
}
