using System;

namespace RAG.Domain.DTOs.Job
{
    public class AsyncUploadResponse
    {
        public Guid JobId { get; set; }
        public string Status { get; set; } = "pending";
        public string Message { get; set; } = "Upload started. Use jobId to check progress.";
    }
}