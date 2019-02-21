classdef udpcam_remote_control < handle
    properties
        IP@char='127.0.0.1'
        RemotePort@double=4010;
        LocalPort@double=4011;
        Log=[];
        Verbose@logical=true;
    end
    properties (GetAccess=public,SetAccess=private)
        RogerRoger=[];
    end
    properties (Access=private)
        udp_obj;
    end
    methods
        function O=udpcam_remote_control
            % see also: instrreset
            try
            init_udp_obj(O)
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
            if strcmpi(strtrim(msg),'Roger')
                O.RogerRoger=true;
                return
            end
            if O.Verbose
                fprintf('%s\n',msg);
            end
            O.append_log('them',msg);
        end
        function send(O,varargin)
            if numel(varargin)>0
                msg=sprintf(varargin{:});
                fprintf(O.udp_obj,msg);
                O.append_log('us',msg);
                O.RogerRoger=false;
            end
        end
        
        
           function append_log(O,sender,msg)
            when={datestr(now,'YYYYMMDD_hhmmss')};
            who={sender};
            what={msg};
            O.Log=[O.Log ; table(when,who,what)];
        end
    end
    methods (Access=private)
        function init_udp_obj(O)
            if ~isempty(O.udp_obj) && isvalid(O.udp_obj)
                fclose(O.udp_obj);
            end
            O.udp_obj=udp(O.IP,'RemotePort',O.RemotePort,'LocalPort',O.LocalPort);
            O.udp_obj.DatagramReceivedFcn = @O.disp_cam_message;
            fopen(O.udp_obj);
        end
     
    end
    
    methods
        function set.IP(O,x)
            nums=cellfun(@str2double,regexp(x,'\.','split'));
            if numel(nums)~=4 || ~all(nums>=0 & nums<=255)
                error('%s is not a valid IP address',x);
            end
            O.IP=x;
            init_udp_obj(O)
        end
        function set.RemotePort(O,x)
            if mod(x,1)~=0
                error('Port number must be whole');
            end
            if x<1024 && x>49151
                error('Valid port numbers are between 1024 and 49151');
            end
            O.RemotePort=x;
            init_udp_obj(O)
        end
        function set.LocalPort(O,x)
            if mod(x,1)~=0
                error('Port number must be whole');
            end
            if x<1024 && x>49151
                error('Valid port numbers are between 1024 and 49151');
            end
            O.LocalPort=x;
            init_udp_obj(O)
        end
    end
end



