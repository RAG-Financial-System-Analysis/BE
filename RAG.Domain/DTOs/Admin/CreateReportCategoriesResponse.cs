using System;
using System.Collections.Generic;
using System.Text;

namespace RAG.Domain.DTOs.Admin
{
    public class CreateReportCategoriesResponse
    {
        public Guid Id { get; set; }
        public string? Message { get; set; }
    }
}
