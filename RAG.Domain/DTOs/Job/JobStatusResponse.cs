using System;

namespace RAG.Domain.DTOs.Job
{
    public class JobStatusResponse
    {
        public Guid JobId { get; set; }
        public string Status { get; set; } = null!; // "pending", "processing", "completed", "failed"
        public int Progress { get; set; } // 0-100
        public string? ErrorMessage { get; set; }
        public DateTime CreatedAt { get; set; }
        public DateTime? UpdatedAt { get; set; }
        public object? Result { get; set; } // Final result when completed
    }
}