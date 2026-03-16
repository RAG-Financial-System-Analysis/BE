using System;

namespace RAG.Domain.DTOs.Job
{
    public class JobData
    {
        public Guid JobId { get; set; }
        public string Status { get; set; } = "pending";
        public int Progress { get; set; } = 0;
        public Guid UserId { get; set; }
        public string JobType { get; set; } = null!; // "upload" or "chat"
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
        public string? ErrorMessage { get; set; }
        public object? InputData { get; set; }
    }
}