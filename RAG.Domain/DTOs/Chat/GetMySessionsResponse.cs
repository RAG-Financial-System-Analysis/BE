using System;
using System.Collections.Generic;

namespace RAG.Domain.DTOs.Chat
{
    public class SessionItemDto
    {
        public Guid Id { get; set; }
        public string Title { get; set; } = string.Empty;
        public string AnalyticsTypeName { get; set; } = string.Empty;
        public DateTime StartTime { get; set; }
        public DateTime? LastMessageAt { get; set; }
        public int MessageCount { get; set; }
    }

    public class GetMySessionsResponse
    {
        public List<SessionItemDto> Sessions { get; set; } = new();
    }
}
