using System;
using System.Collections.Generic;
using System.Linq.Expressions;
using System.Text;

namespace RAG.Application.Interfaces
{
    public interface IRepository<T> where T : class
    {
        Task<T?> GetByIdAsync(Guid id);
        Task<IEnumerable<T>> GetAllAsync();
        Task<IEnumerable<T>> FindAsync(Expression<Func<T, bool>> predicate);

        Task AddAsync(T entity);
        void Update(T entity);
        void Delete(T entity);

        // Hàm lưu xuống DB (nếu muốn gọi thủ công)
        Task SaveChangesAsync();
    }
}
