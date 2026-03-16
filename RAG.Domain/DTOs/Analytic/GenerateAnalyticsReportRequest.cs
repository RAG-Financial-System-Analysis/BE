using System;
using System.ComponentModel.DataAnnotations;

namespace RAG.Domain.DTOs.Analytic
{
    public class GenerateAnalyticsReportRequest
    {
        [Required(ErrorMessage = "SessionId is required")]
        public Guid SessionId { get; set; }
        
        [Required(ErrorMessage = "Title is required")]
        [StringLength(200, ErrorMessage = "Title cannot exceed 200 characters")]
        public string Title { get; set; } = string.Empty;
    }
}
