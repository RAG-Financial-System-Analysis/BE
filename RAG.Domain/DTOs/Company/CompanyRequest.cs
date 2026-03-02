using System;
using System.Collections.Generic;
using System.Text;

namespace RAG.Domain.DTOs.Company
{
    public class CompanyRequest
    {
        public string Ticker { get; set; } = null!;
        public string Name { get; set; } = null!;
        public string? Industry { get; set; }
        public string? Description { get; set; }
        public string? Website { get; set; }
    }
}
