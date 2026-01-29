using System;
using System.Collections.Generic;
using System.Text;

namespace RAG.Domain.DTOs.Auth
{
    public class AuthResponse
    {
        public string AccessToken { get; set; }
        public string IdToken { get; set; }
        public string RefreshToken { get; set; }
        public string Role { get; set; }
        public string FullName { get; set; }
    }
}
