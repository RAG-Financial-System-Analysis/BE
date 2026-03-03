using System;

namespace RAG.Domain.DTOs.Chat
{
    public class CreateChatSessionRequest
    {
        public Guid AnalyticsTypeId { get; set; }
        public string Title { get; set; } = null!;
    }

    public class CreateChatSessionResponse
    {
        public Guid SessionId { get; set; }
        public string? Message { get; set; }
    }
}
