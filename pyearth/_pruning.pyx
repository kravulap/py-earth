# distutils: language = c
# cython: cdivision = True
# cython: boundscheck = False
# cython: wraparound = False
# cython: profile = True

from _record cimport PruningPassIteration
from _util import gcv
import numpy as np

cdef class PruningPasser:
    '''Implements the generic pruning pass as described by Friedman, 1991.'''
    def __init__(PruningPasser self, Basis basis, cnp.ndarray[FLOAT_t, ndim=2] X, cnp.ndarray[FLOAT_t, ndim=1] y, **kwargs):
        self.X = X
        self.m = self.X.shape[0]
        self.n = self.X.shape[1]
        self.y = y
        self.basis = basis
        self.B = np.empty(shape=(self.m,len(self.basis)+1),dtype=np.float)
        self.penalty = kwargs['penalty'] if 'penalty' in kwargs else 3.0
        self.sst = np.std(self.y)**2
        
    cpdef run(PruningPasser self):
        #This is a totally naive implementation and could potentially be made faster 
        #through the use of updating algorithms.  It is not clear that such 
        #optimization would be worthwhile, as the pruning pass is not the slowest
        #part of the algorithm.
        cdef unsigned int i
        cdef unsigned int j
        cdef unsigned int basis_size = len(self.basis)
        cdef unsigned int pruned_basis_size = self.basis.plen()
        cdef FLOAT_t gcv_
        cdef unsigned int best_iteration
        cdef unsigned int best_bf_to_prune
        cdef FLOAT_t best_gcv
        cdef FLOAT_t best_iteration_gcv
        cdef FLOAT_t best_iteration_mse
        
        cdef cnp.ndarray[FLOAT_t, ndim=2] B = <cnp.ndarray[FLOAT_t, ndim=2]> self.B
        cdef cnp.ndarray[FLOAT_t, ndim=2] X = <cnp.ndarray[FLOAT_t, ndim=2]> self.X
        cdef cnp.ndarray[FLOAT_t, ndim=1] y = <cnp.ndarray[FLOAT_t, ndim=1]> self.y
        
        #Initial solution
        self.basis.transform(self.X,self.B)
        beta, mse = np.linalg.lstsq(B[:,0:(basis_size)],self.y)[0:2]
        if mse:
            mse /= self.m
        else:
            mse = (1.0/self.m)*np.sum((np.dot(B[:,0:basis_size],beta) - self.y)**2)

        #Create the record object
        self.record = PruningPassRecord(self.m,self.n,self.penalty,self.sst,pruned_basis_size,mse)
        gcv_ = self.record.gcv(0)
        best_gcv = gcv_
        best_iteration = 0
        
        #Prune basis functions sequentially
        for i in range(1,pruned_basis_size):
            first = True
            pruned_basis_size -= 1
            
            #Find the best basis function to prune
            for j in range(basis_size):
                bf = self.basis[j]
                if bf.is_pruned():
                    continue
                if not bf.is_prunable():
                    continue
                bf.prune()
                self.basis.transform(self.X, B)
                beta, mse = np.linalg.lstsq(B[:,0:pruned_basis_size],y)[0:2]
                if mse:
                    mse /= self.m
                else:
                    mse = (1/float(self.m))*np.sum((np.dot(B[:,0:pruned_basis_size],beta) - y)**2)
                gcv_ = gcv(mse,pruned_basis_size,self.m,self.penalty)
                
                if gcv_ <= best_iteration_gcv or first:
                    best_iteration_gcv = gcv_
                    best_iteration_mse = mse
                    best_bf_to_prune = j
                bf.unprune()
            
            #The inner loop found the best basis function to remove for this iteration.
            #Now check whether this iteration is better than all the previous ones.
            if best_iteration_gcv <= best_gcv:
                best_gcv = best_iteration_gcv
                best_iteration = i
                
            #Update the record and prune the selected basis function
            self.record.append(PruningPassIteration(best_bf_to_prune,pruned_basis_size,best_iteration_mse))
            self.basis[best_bf_to_prune].prune()
            
        #Unprune the basis functions pruned after the best iteration
        self.record.set_selected(best_iteration)
        self.record.roll_back(self.basis)
        
    cpdef PruningPassRecord trace(PruningPasser self):
        return self.record
    
    
    
    