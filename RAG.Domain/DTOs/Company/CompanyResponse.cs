using System;
using System.Collections.Generic;
using System.Text;

namespace RAG.Domain.DTOs.Company
{
    public class CompanyResponse
    {
        public Guid Id { get; set; }
        public string? Ticker { get; set; }
        public string? Name { get; set; }
        public string? Industry { get; set; }
        public string? Description { get; set; }
        public string? Website { get; set; }
        public DateTime? CreatedAt { get; set; }
    }
}
