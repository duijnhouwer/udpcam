classdef vidtest <handle
    
    properties
        asd
    end
    methods 
        function [a,b]=vidtest(profile)
            h=figure;
            drawnow
            b=VideoWriter('asd',profile);
            uiwait(h);
        end
    end
end