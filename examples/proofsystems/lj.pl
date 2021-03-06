%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%                                           %
% SELLF specification for LJ                %
%                                           %
% Elaine Pimentel   -   2012                %
%                                           %
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

subexp r lin. % lin -> Forces singleton on rhs for init
subexp l unb. % unb -> Implicit weakening on init

%% For printing object level rules.
subexpctx l many ant.
subexpctx r single suc.

%subexprel r < l. %% optional

rules introduction.

% Implication
not (lft (imp A B)) *  ![l] ?[r] (rght A) * ?[l] (lft B).
not (rght (imp A B)) *  ![l] (?[l] (lft A) | ?[r] (rght B)).

% Conjunction
not (lft (and A B)) * ?[l] (lft A) + ?[l] (lft B).
not (rght (and A B)) * ![l] (?[r] (rght A) & ?[r] (rght B)).

% Disjunction
not (lft (or A B)) * ?[l] (lft A) & ?[l] (lft B).
not (rght (or A B)) * ![l] ?[r] (rght A) + ![l] ?[r] (rght B).

% False
not (lft false) * top.

% True
not (rght true) * top.

rules axiom.
not (lft A) * not (rght A).

rules cut.
![l] ?[r] (rght A) * ?[l] (lft A).
