using System;
using System.Collections.Generic;
using System.Text;

namespace RAG.Domain.DTOs.Analytic
{
    public class AnalyticTypeDto
    {
        public Guid Id { get; set; }
        public string Name { get; set; } = null!;
        public string Code { get; set; } = null!;   
        public string? Description { get; set; } 
    }
}
