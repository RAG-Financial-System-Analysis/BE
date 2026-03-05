using System;
using System.Collections.Generic;
using System.Text;

namespace RAG.Domain.DTOs.Analytic
{
    public class GetAnalyticTypeResponse
    {
        public List<AnalyticTypeDto> AnalyticTypes { get; set; } = new List<AnalyticTypeDto>(); 

    }
}
