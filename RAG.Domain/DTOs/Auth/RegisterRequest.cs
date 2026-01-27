using System;
using System.Collections.Generic;
using System.Text;

namespace RAG.Domain.DTOs.Auth
{
    public class RegisterRequest
    {
        public string Email { get; set; }
        public string Password { get; set; }    
        public string FullName { get; set; }
    }
}
