function s = propvals(obj,opt)
    
    %PROPVALS - Return object properties and their values as a struct.
    %
    %   S = PROPVALS(OBJ) returns the properties of object OBJ and their
    %   values as a struct S. 
    %
    %   PROPVALS(OBJ,'set') return only the subset with public SetAccess.
    %
    %   PROPVALS(OBJ,'all') is identical to PROPVALS(OBJ).
    %
    %   fieldnames(PROPVALS(OBJ)) and fieldnames(PROPVALS(OBJ),'all') are
    %   identical to properties(OBJ).
    %
    %   If there are no (matching) properties in obj, S will be an empty
    %   array [].
    %
    %   Example:
    %       v = VideoWriter('test.mp4','MPEG-4')
    %       allp = propvals(v) 
    %       setp = propvals(v,'set')
    %
    %   See also: properties, fieldnames
    
    %   Duijnhouwer 2019-2-18
    
    narginchk(1,2)
    props=properties(obj);
    
    if nargin==1
        opt='all';
    elseif ~any(strcmpi(opt,{'set','all'}))
        error('Argument #2 must be ''all'', ''set'', or omitted.')
    end
    
    if strcmpi(opt,'set')
        canset=true(numel(props),1);
        for i=1:numel(props)
            
            % the following two lines are more elegant then trying to set a
            % property and catching exceptions (which is annoying to rely
            % on by design because it trips constantly when debugging with
            % 'dbstop if error' activated. Unfortunately it throws errors
            % for classes based of hsdynamic properties (such as an instance webcam). So if
            % this method fails, try the old method of attempting to assing
            % a value
            try
                tmp=findprop(obj,props{i});
                canset(i)=strcmp(tmp.SetAccess,'public');
            catch me
                if ~strcmpi(me.identifier,'MATLAB:class:InvalidBaseClass')
                    % unexpected, not because of dynamic property
                    warning(me.message);
                end
                try
                    obj.(props{i})=obj.(props{i});
                catch me
                    if strcmpi(me.identifier,'MATLAB:class:SetProhibited')
                        % error expected when prop is not settable
                    	canset(i)=false;
                    else
                        rethrow(me);
                    end
                end
            end
        end
        props=props(canset);
    end
    
    s=[];
    for i=1:numel(props)
        s.(props{i})=obj.(props{i});
    end 
    
end
