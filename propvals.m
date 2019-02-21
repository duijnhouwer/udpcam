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
            tmp=findprop(obj,props{i});
            canset(i)=strcmp(tmp.SetAccess,'public');
        end
        props=props(canset);
    end
    
    s=[];
    for i=1:numel(props)
        s.(props{i})=obj.(props{i});
    end 
    
end