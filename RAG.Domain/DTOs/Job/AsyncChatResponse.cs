using System;

namespace RAG.Domain.DTOs.Job
{
    public class AsyncChatResponse
    {
        public Guid JobId { get; set; }
        public string Status { get; set; } = "pending";
        public string Message { get; set; } = "Chat processing started. Use jobId to check progress.";
    }
}