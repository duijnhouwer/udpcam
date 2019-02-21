function [scum,vars]=skim(vars,name,varargin)
    
    % Skim names, name-value pairs, or name-valuelists pairs from a cell
    % array
    %
    % See also inputParser
    
    narginchk(2,inf)
    if ~iscell(vars)
        error('Argument 1 must be a cell');
    elseif ~ischar(name)
        error('Argument 2 must be a string');
    elseif ~all(cellfun(@(x)isa(x,'function_handle'),varargin))
        error('Arguments 3 and beyond must be function handles');
    end
    n_values=numel(varargin);
    idx=find(strcmpi(name,vars));
    if isempty(idx)
        % the name is not in vars list
        scum='';
        return;
    elseif n_values==0
        scum=name; % name is a toggle
        return
    elseif idx+n_values>numel(vars)
        error('found ''%s'' in list but not followed by the requested number of values (%d)',name,n_values);
    else
        scum=vars(idx+1:idx+n_values); % cell array
    end
    % check if the values meet their requirements
    for i=1:n_values
        ok(i)=feval(varargin{i},scum{i});
    end
    % make a non-cell output if n_values==1
    if n_values==1
        scum=scum{1};
    end
    % remove the name and it's values from the vars list
    vars(idx:idx+n_values)=[];
end
    
    
    
    