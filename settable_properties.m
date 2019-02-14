function s = settable_properties(obj)
    
    % settable_properties - Return properties of an object with set access
    % as a struct
    %
    % Example:
    %   v = VideoWriter('test')
    %   settable_properties(v)
    %   fieldnames(settable_properties(v))
    %
    % See also: properties, fieldnames
    
    % Duijnhouwer 2019-2-6
    
    allprops=properties(obj);
    issettable=true(numel(allprops),1);
    for i=1:numel(allprops)
        prp=findprop(obj,allprops{i});
        issettable(i)=strcmp(prp.SetAccess,'public');
    end
    setprops=allprops(issettable);
    for i=1:numel(setprops)
        s.(setprops{i})=obj.(setprops{i});
    end 
end