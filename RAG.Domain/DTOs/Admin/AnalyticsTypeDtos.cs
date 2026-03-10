using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;

namespace RAG.Domain.DTOs.Admin
{
    // ── Report Categories (For Analysts) ──────────────────────────────────────
    public class GetReportCategoriesForAnalystResponse
    {
        public List<ReportCategorySimpleDto> Categories { get; set; } = new();
    }

    public class ReportCategorySimpleDto
    {
        public Guid Id { get; set; }
        public string Name { get; set; } = null!;
        public string? Description { get; set; }
    }

    // ── Analytics Types ────────────────────────────────────────────────────────
    public class CreateAnalyticsTypeRequest
    {
        [Required(ErrorMessage = "Code is required")]
        [MaxLength(50, ErrorMessage = "Code exceeds 50 characters")]
        public string Code { get; set; } = null!;

        [Required(ErrorMessage = "Name is required")]
        [MaxLength(255, ErrorMessage = "Name exceeds 255 characters")]
        public string Name { get; set; } = null!;

        [MaxLength(500, ErrorMessage = "Description exceeds 500 characters")]
        public string? Description { get; set; }
    }

    public class CreateAnalyticsTypeResponse
    {
        public Guid Id { get; set; }
        public string? Message { get; set; }
    }

    public class UpdateAnalyticsTypeRequest
    {
        [Required(ErrorMessage = "Code is required")]
        [MaxLength(50, ErrorMessage = "Code exceeds 50 characters")]
        public string Code { get; set; } = null!;

        [Required(ErrorMessage = "Name is required")]
        [MaxLength(255, ErrorMessage = "Name exceeds 255 characters")]
        public string Name { get; set; } = null!;

        [MaxLength(500, ErrorMessage = "Description exceeds 500 characters")]
        public string? Description { get; set; }
    }
}
