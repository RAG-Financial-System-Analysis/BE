using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;

namespace RAG.Domain.DTOs.Admin
{
    public class GetReportCategoryByIdResponse
    {
        public Guid Id { get; set; }
        public string Name { get; set; } = null!;
        public string? Description { get; set; }
        public int AssociatedReportsCount { get; set; }
        public List<AssociatedReportDto> AssociatedReports { get; set; } = new();
    }

    public class AssociatedReportDto
    {
        public Guid Id { get; set; }
        public string Title { get; set; } = null!;
        public string CompanyName { get; set; } = null!;
        public DateTime? CreatedAt { get; set; }
    }

    public class UpdateReportCategoryRequest
    {
        [Required(ErrorMessage = "Name is required")]
        [MaxLength(100, ErrorMessage = "Name exceeds 100 characters")]
        public string Name { get; set; } = null!;

        [MaxLength(500, ErrorMessage = "Description exceeds 500 characters")]
        public string? Description { get; set; }
    }
}
