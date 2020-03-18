function [match]=partialMatch(str,targets,varargin)
    
    p=inputParser;
    p.addRequired('str',@ischar);
    p.addRequired('targets',@(x)iscell(x)&&all(cellfun(@ischar,targets)));
    p.addParameter('IgnoreCase',false,@islogical);
    p.addParameter('FullMatchPrecedence',true,@islogical);
    p.parse(str,targets,varargin{:});
    
    if p.Results.IgnoreCase
        str=lower(p.Results.str);
        targets=lower(p.Results.targets);
    else
         str=p.Results.str;   
         targets=p.Results.targets;
    end
    
    match={};
    if p.Results.FullMatchPrecedence
        match=p.Results.targets(strcmp(targets,str));
    end
    if numel(match)==0
        % try partial matching
        match=p.Results.targets(startsWith(targets,str));
    end
end
