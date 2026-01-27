using System;
using System.Collections.Generic;
using System.Text;

namespace RAG.Domain.DTOs.Auth
{
    public class VerifyRequest
    {
        public string Email { get; set; }
        public string Code { get; set; } 
    }
}
