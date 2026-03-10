using System;
using System.Collections.Generic;
using System.ComponentModel.DataAnnotations;
using System.Text;

namespace RAG.Domain.DTOs.Admin
{
    public class CreateReportCategoriesRequest
    {
        [Required(ErrorMessage = "Name is required")]
        [MaxLength(100, ErrorMessage = "Name exceeds 100 characters")]
        public string Name { get; set; }

        [MaxLength(500, ErrorMessage = "Description exceeds 500 characters")]
        public string Description { get; set; }
    }
}
