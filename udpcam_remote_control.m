classdef udpcam_remote_control < handle
    
    properties
        hostip='127.0.0.1'
        remoteport=4010;
        localport=4011;
        verbosity='all';
    end
    properties (Access=private)
        udp_obj;
    end
    methods
        function O=udpcam_remote_control
            try
                init_udp_obj(O);
            catch me
                disp(me.message)
                if strcmpi(me.identifier,'instrument:fopen:opfailed')
                    disp('Tips: delete the object that holds the connection or use <a href="matlab:disp(''instrreset''),instrreset">instrreset</a>');
                    O.delete
                end
            end
        end
        function delete(O)
            if ~isempty(O.udp_obj) && isvalid(O.udp_obj)
                fclose(O.udp_obj);
                delete(O.udp_obj);
            end
        end
        function disp_cam_message(O,~,~)
            msg=strtrim(fscanf(O.udp_obj));
            if strcmpi(O.verbosity,'all') || strcmpi(O.verbosity,'error') && startsWith(lower(msg),'error:')
                fprintf('[%s] %s\n',mfilename,msg);
            end
        end
        function send(O,varargin)
            if numel(varargin)>0
                msg=sprintf('%s',varargin{:});
                fprintf(O.udp_obj,msg);
           end
        end
        
    end
    methods (Access=private)
        function init_udp_obj(O)
            if ~isempty(O.udp_obj) && isvalid(O.udp_obj)
                fclose(O.udp_obj);
            end
            O.udp_obj=udp(O.hostip,'RemotePort',O.remoteport,'LocalPort',O.localport);
            O.udp_obj.Terminator = 13; % 13 ('\r') as opposed to default 11 ('\n'). 
            O.udp_obj.InputBufferSize = 4096;
            O.udp_obj.OutputBufferSize = 4096;
            O.udp_obj.DatagramReceivedFcn = @O.disp_cam_message;
            fopen(O.udp_obj);
        end
    end
    methods
        function set.hostip(O,x)
            nums=cellfun(@str2double,regexp(x,'\.','split'));
            if numel(nums)~=4 || ~all(nums>=0 & nums<=255)
                error('%s is not a valid host ip address',x);
            end
            O.hostip=x;
            init_udp_obj(O)
        end
        function set.remoteport(O,x)
            if mod(x,1)~=0
                error('Port number must be whole');
            end
            if x<1024 && x>49151
                error('Valid port numbers are between 1024 and 49151');
            end
            O.remoteport=x;
            init_udp_obj(O)
        end
        function set.localport(O,x)
            if mod(x,1)~=0
                error('Port number must be whole');
            end
            if x<1024 && x>49151
                error('Valid port numbers are between 1024 and 49151');
            end
            O.localport=x;
            init_udp_obj(O)
        end
        function set.verbosity(O,x)
            if ~any(strcmpi(x,{'none','error','all'}))
                error('verbosity should be ''none'',''errors'', or ''all''.');
            end
            O.verbosity=x;
        end
    end
end



