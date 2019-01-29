function u=udpcam_remote_control
    
    % see also: instrreset
    
    localport=4011;
    u=udp('127.0.0.1','RemotePort',4010,'LocalPort',localport);
    u.DatagramReceivedFcn = @disp_cam_message;
    fopen(u);
    
 
end
    


function disp_cam_message(u,~)
    msg= strtrim(fscanf(u));
    fprintf('%s:%d "%s"\n',u.RemoteHost,u.RemotePort,msg);
end
