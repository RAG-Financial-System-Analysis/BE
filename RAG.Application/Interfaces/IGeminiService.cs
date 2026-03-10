using System;
using System.Collections.Generic;
using System.Text;

namespace RAG.Application.Interfaces
{
    public interface IGeminiService
    {
        Task<string> GenerateAsync(string prompt);
        Task<string> ExtractTextFromPdfAsync(byte[] pdfBytes); // NEW: OCR cho PDF ảnh
    }
}