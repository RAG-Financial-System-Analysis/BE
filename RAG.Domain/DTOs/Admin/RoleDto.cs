using System;

namespace RAG.Domain.DTOs.Admin
{
    public class RoleDto
    {
        public Guid Id { get; set; }
        public string Name { get; set; } = string.Empty;
    }
}
