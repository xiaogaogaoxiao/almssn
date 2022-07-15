function [f, g] = maxcut_quad(V, C)
% maxcut SDP: 
% X is n by n matrix
% max Tr(C*X), s.t., X_ii = 1, X psd
%
% low rank model:
% X = V'*V, V = [V_1, ..., V_n], V is a p by n matrix
% max Tr(C*V'*V), s.t., ||V_i|| = 1,
%
% X = V'*V;
% f = sum(sum(C.*X));
% if nargout >= 2
%     g = V*C;
% end
% -------------------------------------
%
% Reference: 
%  Z. Wen and W. Yin
%  A feasible method for optimization with orthogonality constraints
%
% Author: Zaiwen Wen
%   Version 0.1 .... 2010/10
%   Version 0.5 .... 2013/10

% g = V*C;
% f = sum(dot(g,V));

g = 2*(V*C);
f = sum(dot(g,V))/2;

