using System;

namespace RAG.Domain.DTOs.Admin
{
    public class UpdateUserRequest
    {
        public string FullName { get; set; } = string.Empty;
        public Guid RoleId { get; set; }
        public bool IsActive { get; set; }
    }
}
