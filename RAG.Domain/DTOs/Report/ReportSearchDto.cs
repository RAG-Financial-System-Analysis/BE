using System;
using System.Collections.Generic;
using System.Text;

namespace RAG.Domain.DTOs.Report
{
    public class ReportSearchDto
    {
        public Guid Id { get; set; }
        public string? Ticker { get; set; }
        public string? CompanyName { get; set; }
        public int Year { get; set; }
        public string? Period { get; set; }
        public double RelevanceScore { get; set; }
    }

}
