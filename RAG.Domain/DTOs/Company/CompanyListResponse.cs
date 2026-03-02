using System;
using System.Collections.Generic;
using System.Text;

namespace RAG.Domain.DTOs.Company
{
    public class CompanyListResponse
    {
        public int Total { get; set; }
        public int Page { get; set; }
        public int PageSize { get; set; }
        public IEnumerable<CompanyResponse> Data { get; set; } = new List<CompanyResponse>();
    }
}
