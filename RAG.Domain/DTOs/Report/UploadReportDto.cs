using Microsoft.AspNetCore.Http;
using System;
using System.ComponentModel.DataAnnotations;

namespace RAG.Domain.DTOs.Report
{
    public class UploadReportRequest
    {
        [Required]
        public IFormFile File { get; set; } = null!;

        [Required]
        public Guid CompanyId { get; set; }

        [Required]
        public Guid CategoryId { get; set; }

        [Required]
        [Range(2000, 2100)]
        public int Year { get; set; }

        [Required]
        [StringLength(10)]
        public string Period { get; set; } = null!;

        [StringLength(20)]
        public string Visibility { get; set; } = "private";
    }

    public class UploadReportResponse
    {
        public Guid ReportId { get; set; }
        public string Message { get; set; } = null!;
        public int MetricsExtracted { get; set; }
        public int PageCount { get; set; }
        public string PdfType { get; set; } = string.Empty; // NEW: PDF type info
        public List<MetricResponse>? Metrics { get; set; }
    }

    public class MetricResponse
    {
        public string Code { get; set; } = null!;
        public string Name { get; set; } = null!;
        public decimal Value { get; set; }
        public string Unit { get; set; } = null!;
    }
  
}
