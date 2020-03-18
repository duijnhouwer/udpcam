classdef udpcam < handle
    
    % recommended to have Adam Danz' msgboxFontSize on your path for bigger fonts in dialogs
    % https://www.mathworks.com/matlabcentral/fileexchange/68460-msgboxfontsize
    
    properties (Access=private)
        udp_settings
        udp_obj
        fig_obj
        axs_obj
        cam_obj
        vid_obj
        exit_flag=false
        rec_frames=0 % Dual purpose flow-control flag AND counter for frame_grab_s array
        main_menu
        display
        frame
        rec_start_tic
        last_key_press
        frame_grab_s
        video_profile
        overlay
        win_resize_tic % timer since last window resize
        color_space
        resample_after_rec; % make video realtime after recording
        flip_up_down 
        flip_left_right
        rotation
        crop_box
        crop_enable
        open_dialog_name
    end
    
    methods (Access=public)
        function O=udpcam(varargin)
            p=inputParser;
            p.addParameter('IP','127.0.0.1',@ischar);
            p.addParameter('LocalPort',4010,@(x)isnumeric(x) && mod(x,1)==0 && x>=1024 && x<=49151);
            p.addParameter('RemotePort',4011,@(x)isnumeric(x) && mod(x,1)==0 && x>=1024 && x<=49151);
            p.addParameter('position',[260 500 640 480],@(x)isnumeric(x)&&isvector(x)&&numel(x)==4);
            p.addParameter('center',true,@(x)any(x==[1 0]));
            p.addParameter('bgcolor',[0.5 0.5 0.5],@(x)isnumeric(x)&&numel(x)==3&&all(x>=0&x<=1));
            p.parse(varargin{:});
            
            % Initialize the flow control flags and other parameters
            O.exit_flag=false;
            O.rec_frames=0;
            O.rec_start_tic=tic;
            O.last_key_press=[];
            
            % Set the video defaults
            O.video_profile='Archival';
            O.vid_obj=VideoWriter(fullfile(pwd,'vid.mj2'),O.video_profile);
            % store color_space as class scope variable because we need
            % access when menu is changed into "stop recording" only, too
            O.color_space = categorical({'RGB'});
            O.resample_after_rec = false;
            O.flip_up_down=false;
            O.flip_left_right=false; % flip left right
            O.rotation=0;
            O.crop_enable=false;
            O.crop_box=[0 0 1 1];
            
            % Setup the window
            O.fig_obj=figure;
            O.fig_obj.Position=p.Results.position;
            O.fig_obj.Color=p.Results.bgcolor;
            O.fig_obj.Visible='off';
            O.fig_obj.Units='Pixels';
            O.fig_obj.CloseRequestFcn=@O.close_button_callback;
            O.fig_obj.ResizeFcn=@O.maintain_aspect_ratio;
            O.fig_obj.Pointer='watch';
            O.fig_obj.NumberTitle='Off';
            O.fig_obj.MenuBar='none';
            O.fig_obj.ToolBar='none';
            O.fig_obj.Name = [mfilename ' ' p.Results.IP ':' num2str(p.Results.LocalPort)];
            O.fig_obj.WindowKeyPressFcn=@O.key_press_callback;
            if verLessThan('matlab','9.4') % 2018a
                O.fig_obj.WindowState='normal'; % indicated maximized or not, introduced with 2018a
            end
            
            % Create the axes where the preview will be displayed
            O.axs_obj = axes(O.fig_obj);
            O.axs_obj.Units='normalized';
            O.axs_obj.Position=[0 0 1 1];
            box(O.axs_obj,'on');
            hold(O.axs_obj,'off');
            % Initialize the display window
            O.display=image(O.axs_obj,[0 1],[0 1],zeros(1,1,3)); % 1 pixel RGB image to initialize
            % Initialize the overlay
            O.build_overlay;
            % Put at center of screen if requested
            if p.Results.center
                movegui(O.fig_obj,'center')
            end
            % Make the window visible.
            O.fig_obj.Visible = 'on';
            drawnow;
            
            % The cam_obj object
            if ~isempty(webcamlist)
                try
                    O.cam_obj=webcam();
                catch me
                    msg{1}=me.message;
                    if strcmpi(me.identifier,'MATLAB:webcam:connectionExists')
                        msg{end+2}='Tip: run ''clear all classes'' and try again.';
                    end
                    uiwait(O.big_errordlg(msg,mfilename,'modal'));
                    O.clean_up;
                    delete(O);
                    return
                end
            else
                O.cam_obj=[];
            end
            
            % Set up the UDP connection for receiving commands and sending
            % feedback
            O.udp_settings.Enable=true;
            O.udp_settings.RemoteHost=p.Results.IP;
            O.udp_settings.LocalPort=p.Results.LocalPort;
            O.udp_settings.RemotePort=p.Results.RemotePort;
            try
                O.setup_udp_connection;
            catch me
                msg={me.message};
                if strcmpi(me.identifier,'instrument:fopen:opfailed')
                    msg{end+2}='Tip: run ''instrreset'' to release all connections and try again.';
                end
                uiwait(O.big_errordlg(msg,mfilename,'modal'));
                O.clean_up;
                delete(O);
                return
            end
            
            % Create the main right-click context menu
            O.build_main_menu;
            
            % Set open_dialog_name flag, this keeps track if a dialog is
            % open in the gui to block remote control commands
            O.open_dialog_name='';
            
            % Start the loop
            O.main_loop;
            O.clean_up;
            delete(O);
        end
    end
    methods (Access=private)
        function main_loop(O)
            O.fig_obj.Pointer='arrow';
            while ~O.exit_flag && isvalid(O.fig_obj)
                O.grab_frame;
                O.show_frame;
                if O.rec_frames>0
                    O.save_frame
                end
                if ~isempty(O.win_resize_tic) && toc(O.win_resize_tic)>0.1
                    O.resize_figure_to_content;
                    O.win_resize_tic=[];
                end
            end
        end
        
        function close_button_callback(O,~,~)
            set(O.fig_obj, 'pointer', 'watch')
            O.exit_flag=true; % breaks the video loop and makes that uiwait is skipped after coming out of video loop
            % pause(1/4); % give plenty time to finish current cycle of the main_loop
            % O.clean_up;
        end
        
        function key_press_callback(O,~,evt)
            s=toc(O.rec_start_tic); % second since rec start
            if strcmp(evt.Key,'escape') && ~isempty(O.last_key_press) && strcmp(O.last_key_press.key,'escape') && s-O.last_key_press.s<1/3
                O.last_key_press.key='escape-escape'; % detect twice escape within 1/3 of second
            else
                O.last_key_press.key=evt.Key;
            end
            O.last_key_press.s=s;
        end
        
        function setup_udp_connection(O)
            if ~isempty(O.udp_obj)
                fclose(O.udp_obj);
                delete(O.udp_obj)
                O.udp_obj=[];
            end
            O.udp_obj=udp(O.udp_settings.RemoteHost,'RemotePort',O.udp_settings.RemotePort,'LocalPort',O.udp_settings.LocalPort);
            O.udp_obj.DatagramReceivedFcn = @O.parse_udp_message;
            O.udp_obj.Terminator = 13; % 13 ('\r') as opposed to default 11 ('\n').
            O.udp_obj.InputBufferSize = 4096;
            O.udp_obj.OutputBufferSize = 4096;
            fopen(O.udp_obj);
            O.hello_callback
        end
        
        function parse_udp_message(O,~,~)
            % Parse the message
            if ~isempty(O.open_dialog_name)
                O.send_err(sprintf('%s can''t receive messages at this time because the %s dialog is open.',upper(O.fig_obj.Name),O.open_dialog_name));
            	return;
            end
            msg=strtrim(fscanf(O.udp_obj));
            commands=cellfun(@strtrim,regexp(msg,'>','split'),'UniformOutput',false); % e.g. 'Color Space > RGB' --> {'Color Space'}    {'RGB'}
            currentmenu=O.main_menu;
            for i=1:numel(commands)
                labels={currentmenu.Children.Label};
                match=partialMatch(commands{i},labels,'IgnoreCase',true,'FullMatchPrecedence',true);
                if numel(match)~=1
                    O.send_err(sprintf('No (partial) match for ''%s''',commands{i}));
                    return
                elseif numel(match)>1
                    O.send_err(sprintf('Multiple (%d) matches for ''%s''',numel(match),commands{i}));
                    return
                end
                currentmenu=findobj(currentmenu.Children,'flat','Label',match{1});
                if ~isempty(currentmenu.MenuSelectedFcn)
                    % Found the executable menu item, stop searching
                    break;
                end
            end
            try
                % Execute the associated function with the optional command
                if numel(commands)==i
                    feval(currentmenu.MenuSelectedFcn,currentmenu,'UDP');
                elseif numel(commands)==i+1 % there is one remaining commands
                    feval(currentmenu.MenuSelectedFcn,currentmenu,'UDP',commands{i+1});
                elseif numel(commands)>i+1 % there are more than 1 remaining commands
                    O.send_err(sprintf('Too many commands after %s>',commands{i}));
                end
            catch me
                O.send_err(me.message);
            end
        end
        
        function O=build_main_menu(O)
            delete(O.main_menu);
            O.main_menu = uicontextmenu;
            if ~O.rec_frames>0
                uimenu('Parent',O.main_menu,'Label','UDP');
                uimenu('Parent',O.main_menu,'Label','Camera');
                uimenu('Parent',O.main_menu,'Label','Output');
                uimenu('Parent',O.main_menu,'Label','Record','Separator','on','Callback',@O.start_recording);
                uimenu('Parent',O.main_menu,'Label','Quit','Separator','on','Callback',@O.close_button_callback);
                O.build_udp_menu;
                O.build_camera_menu;
                O.build_output_menu;
            else
                uimenu('Parent',O.main_menu,'Label','Stop Recording','Callback',@O.stop_recording);
            end
            % Attach the menu to the display
            O.display.UIContextMenu=O.main_menu;
        end
        
        function build_udp_menu(O,~,~)
            udp_menu=findobj(O.main_menu.Children,'flat','Label','UDP');
            delete(udp_menu.Children);
            uimenu('Parent',udp_menu,'Label','Settings...','Callback',@O.edit_udp_connection);
            uimenu('Parent',udp_menu,'Label','Hello','Callback',@(src,evt)hello_callback(O,src,evt));
             
            
            uimenu('Parent',udp_menu,'Label','List commands','Callback',@(src,evt)O.list_commands_callback(src,evt));
             
        end
        
        function hello_callback(O,~,~)
              O.send_msg(sprintf('Hello! This is %s on camera %s!',upper(O.fig_obj.Name),O.cam_obj.Name));
        end
        
        function build_camera_menu(O,~,~)
            cam_menu=findobj(O.main_menu.Children,'flat','Label','Camera');
            delete(cam_menu.Children);
            selectMenu=uimenu('Parent',cam_menu,'Label','Select');
            cams=[webcamlist; 'None'];
            for i=1:numel(cams)
                uimenu('Parent',selectMenu,'Label',cams{i},'Callback',@O.select_camera);
            end
            uimenu('Parent',selectMenu,'Label','Refresh List','Callback',@O.build_camera_menu,'Separator','on');
            if ~isempty(O.cam_obj) && isvalid(O.cam_obj)
                O.select_camera(findobj(selectMenu.Children,'flat','Label',O.cam_obj.Name));
            else
                set(findobj(selectMenu.Children,'flat','Label','None'),'Checked','on')
            end
        end
        
        function build_output_menu(O,~,~)
            outMenu=findobj(O.main_menu.Children,'flat','Label','Output');
            delete(outMenu.Children);
            uimenu('Parent',outMenu,'Label','VideoWriter...','Callback',@O.edit_output_settings);
            uimenu('Parent',outMenu,'Label','Resample','Checked',O.onoff(O.resample_after_rec),'Callback',@O.toggle_resample,'Tag','resample_video_check');
        end
        
        function select_camera(O,src,~)
            cam_name=src.Text;
            set(src.Parent.Children,'Checked','off');
            src.Checked='on';
            delete(O.cam_obj);
            if strcmpi(cam_name,'None')
                O.build_camera_menu;
            else
                % select the cam_obj
                try
                    O.cam_obj=webcam(cam_name);
                catch me
                    disp(['select_camera - ' me.message]);
                    return
                end
                % Add dynamic menus to cam_obj menu (depending on
                % availability of a cam_obj and its make and model)
                cam_menu=findobj(O.main_menu.Children,'flat','Label','Camera');
                % - Add the Resolution menu
                resos=O.cam_obj.AvailableResolutions;
                [~,idx]=sort(cellfun(@(x)prod(cellfun(@str2double,regexp(x,'x','split'))),resos),'descend'); % order resos by ...
                resos=resos(idx);                                                                         % ... number of pixels
                delete(findobj(cam_menu.Children,'flat','Label','Resolution'));
                resMenu=uimenu('Parent',cam_menu,'Label','Resolution');
                for i=1:numel(resos)
                    uimenu('Parent',resMenu,'Label',resos{i},'Callback',@(src,evt)O.select_resolution(src,evt));
                end
                set(findobj(resMenu.Children,'flat','Label',O.cam_obj.Resolution),'Checked','on');
                % -
                delete(findobj(cam_menu.Children,'flat','Label','Mirror'));
                mirrorMenu=uimenu('Parent',cam_menu,'Label','Mirror');
                uimenu('Parent',mirrorMenu,'Label','Up-Down','Checked',O.onoff(O.flip_up_down),'Callback',@O.toggle_flip_up_down,'Tag','mirror_up_down_check');
                uimenu('Parent',mirrorMenu,'Label','Left-Right','Checked',O.onoff(O.flip_left_right),'Callback',@O.toggle_flip_left_right,'Tag','mirror_left_right_check');
                delete(findobj(cam_menu.Children,'flat','Label','Rotate'));
                % -
                rotate_menu=uimenu('Parent',cam_menu,'Label','Rotate');
                uimenu('Parent',rotate_menu,'Label','0','Callback',@O.select_rotation);
                uimenu('Parent',rotate_menu,'Label','90','Callback',@O.select_rotation);
                uimenu('Parent',rotate_menu,'Label','180','Callback',@O.select_rotation);
                uimenu('Parent',rotate_menu,'Label','270','Callback',@O.select_rotation);
                set(findobj(rotate_menu.Children,'flat','Label',O.rotation),'Checked','on');
                % -
                crop_menu=uimenu('Parent',cam_menu,'Label','Crop');
                uimenu('Parent',crop_menu,'Label','Enable','Checked',O.onoff(O.crop_enable),'Callback',@O.toggle_crop,'Tag','crop_box_enable_check');
                uimenu('Parent',crop_menu,'Label','Edit box...','Callback',@O.edit_crop_box);
                uimenu('Parent',crop_menu,'Label','Draw box...','Callback',@O.draw_crop_box)
                % - Add the color-space selection menu
                spaces={'RGB','Grayscale','R','G','B'};
                delete(findobj(cam_menu.Children,'flat','Label','Color Space'));
                color_menu=uimenu('Parent',cam_menu,'Label','Color Space');
                for i=1:numel(spaces)
                    uimenu('Parent',color_menu,'Label',spaces{i},'Callback',@O.select_color);
                end
                set(findobj(color_menu.Children,'flat','Label',O.color_space),'Checked','on')
                % - Add the advanced option menu
                delete(findobj(cam_menu.Children,'flat','Label','Advanced Settings...'));
                uimenu('Parent',cam_menu,'Label','Advanced Settings...','Callback',@O.edit_advanced_camera_settings);
            end
        end
        
        function O=select_resolution(O,src,~)
            if ~isempty(O.cam_obj) && isvalid(O.cam_obj)
                O.cam_obj.Resolution=src.Text;
                %O.grab_frame; % to flush possibly lingering frame of previous resolution
                set(src.Parent.Children,'Checked','off');
                src.Checked='on';
            end
        end
        
        function O=select_rotation(O,src,~)
            old_rot=O.rotation;
            O.rotation=str2double(src.Text);
            if O.rotation==old_rot
                return
            end
            %O.grab_frame; % to flush possibly lingering frame of previous resolution
            set(src.Parent.Children,'Checked','off');
            src.Checked='on';
            if mod(old_rot-O.rotation,180)
                % change the window size if aspect ratio flipped
                if ~strcmpi(O.fig_obj.WindowState,'maximized')
                    oldwid=O.fig_obj.Position(3);
                    O.fig_obj.Position(3)=O.fig_obj.Position(4);
                    O.fig_obj.Position(4)=oldwid;
                end
            end
        end
        
        function select_color(O,src,~)
            set(src.Parent.Children,'Checked','off');
            src.Checked='on';
            O.color_space=categorical({src.Text});
        end
        
        function toggle_resample(O,~,~)
            % could use src (2nd argument) instead of using findobj but
            % this way the toggle can be applied in code instead of just
            % through a click on the menu item
            O.resample_after_rec=~O.resample_after_rec;
            obj=findobj(O.fig_obj.Children,'Tag','resample_video_check');
            obj.Checked=O.onoff(O.resample_after_rec);
        end
        
        function toggle_flip_up_down(O,~,~)
            O.flip_up_down=~O.flip_up_down;
            obj=findobj(O.fig_obj.Children,'Tag','mirror_up_down_check');
            obj.Checked=O.onoff(O.flip_up_down);
        end
        function toggle_flip_left_right(O,~,~)
            O.flip_left_right=~O.flip_left_right;
            obj=findobj(O.fig_obj.Children,'Tag','mirror_left_right_check');
            obj.Checked=O.onoff(O.flip_left_right);
        end
        
        function toggle_crop(O,~,~)
            O.crop_enable=~O.crop_enable;
            obj=findobj(O.fig_obj.Children,'Tag','crop_box_enable_check');
            obj.Checked=O.onoff(O.crop_enable);
        end
        
        
        function edit_udp_connection(O,~,source,assignstr)
            % assignstr e.g. 'enable=1'
            tmpset=O.udp_settings;
            switch O.gui_or_udp(source)
                case 'GUI'
                    while true
                        tit='UDP Settings';
                        tit(end+1:end+42-numel(tit))=' ';
                        O.open_dialog_name='UDP Settings';
                        [tmpset,pressedOk]=guisetstruct(tmpset,tit,8);
                        O.open_dialog_name='';
                        if ~pressedOk
                            return; % user changed their mind, no changes will be made
                        end
                        errstr=check_for_errors(tmpset);
                        if ~isempty(errstr)
                            uiwait(O.big_errordlg(strsplit(errstr,'\n'),mfilename,'modal'));
                        else
                            break; % the while loop
                        end
                    end
                case 'UDP'
                    tmpset=O.parse_assignment_string(tmpset,assignstr);
                    error(check_for_errors(tmpset)); % throws no error if argument is empty
            end
            % Don't check for change, make a new connection regardless
            O.udp_settings=tmpset;
            O.setup_udp_connection;
            %
            function errstr=check_for_errors(set)
                errstr='';
                if ~islogical(set.Enable) && ~any(set.Enable==[1 0])
                    errstr=sprintf('%s\n%s',errstr,'Enable must be true or false or 1 or 0');
                end
                if ~ischar(set.RemoteHost)
                    errstr=sprintf('%s\n%s',errstr,'RemoteHost must be a string');
                end
                if ~isnumeric(set.LocalPort)
                    errstr=sprintf('%s\n%s',errstr,'port must be a number');
                end
                if ~isnumeric(set.RemotePort)
                    errstr=sprintf('%s\n%s',errstr,'port must be a number');
                end
            end
        end
        
        function edit_crop_box(O,~,source,assignstr)
            tmpset.Middle_X=O.crop_box(1)+O.crop_box(3)/2;
            tmpset.Middle_Y=O.crop_box(2)+O.crop_box(4)/2;
            tmpset.Width=O.crop_box(3);
            tmpset.Height=O.crop_box(4);
            switch O.gui_or_udp(source)
                case 'GUI'
                    while true
                        tit='Crop Settings (Normalized)';
                        tit(end+1:end+42-numel(tit))=' ';
                        [tmpset,pressedOk]=guisetstruct(tmpset,tit,15);
                        if ~pressedOk
                            return; % user changed their mind, no changes will be made
                        end
                        errstr=check_for_errors(tmpset);
                        if ~isempty(errstr)
                            uiwait(O.big_errordlg(strsplit(errstr,'\n'),mfilename,'modal'));
                        else
                            break; % the while loop
                        end
                    end
                case 'UDP'
                    tmpset=O.parse_assignment_string(tmpset,assignstr);
                    error(check_for_errors(tmpset)); % throws no error if argument is empty
            end
            O.crop_box=[tmpset.Middle_X-tmpset.Width/2 tmpset.Middle_Y-tmpset.Height/2 tmpset.Width tmpset.Height];
            %
            function errstr=check_for_errors(set)
                errstr='';
                if ~isnumeric(set.Middle_X) || set.Middle_X<0 || set.Middle_X>1
                    errstr=sprintf('%s\n%s',errstr,'Middle_X must be a number between 0 and 1');
                end
                if ~isnumeric(set.Middle_Y) || set.Middle_Y<0 || set.Middle_Y>1
                    errstr=sprintf('%s\n%s',errstr,'Middle_Y must be a number between 0 and 1');
                end
                if ~isnumeric(set.Width) || set.Width<0 || set.Width>1
                    errstr=sprintf('%s\n%s',errstr,'Width must be a number between 0 and 1');
                end
                if ~isnumeric(set.Height) || set.Height<0 || set.Height>1
                    errstr=sprintf('%s\n%s',errstr,'Height must be a number between 0 and 1');
                end
            end
        end
        
        function draw_crop_box(O,~,~)
            if O.crop_enable
                % switch to full frame, nested cropping is a little
                % complicated, no need to implement
                O.toggle_crop;
                O.grab_frame;
                O.show_frame;
                O.resize_figure_to_content;
            end
            h = images.roi.Rectangle(O.axs_obj,'Position',O.crop_box,'StripeColor','w');
            drawnow
            while isvalid(h)
                newbox=h.Position;
                pause(0.01)
            end
            delete(h);
            O.crop_box=newbox;
            if ~O.crop_enable
                O.toggle_crop;
            end
        end
        
        function edit_advanced_camera_settings(O,~,source,assignstr)
            oldset=propvals(O.cam_obj,'set');
            % remove the unadvanced settings (that are covered elsewhere in the GUI)
            oldset=rmfield(oldset,'Resolution');
            switch O.gui_or_udp(source)
                case 'GUI'
                    while true
                        label='Advanced Camera Settings';
                        O.open_dialog_name=label;
                        label(end+1:end+42-numel(label))=' '; % add space to stretch window
                        [newset,pressedOk]=guisetstruct(oldset,label,20);
                        O.open_dialog_name='';
                        if ~pressedOk
                            return; % user changed their mind, no changes will be made
                        end
                        errstr=try_apply(newset,oldset);
                        if ~isempty(errstr)
                            uiwait(O.big_errordlg(strsplit(errstr,'\n'),mfilename,'modal'));
                        else
                            break; % the while loop
                        end
                    end
                case 'UDP'
                    newset=O.parse_assignment_string(oldset,assignstr);
                    error(try_apply(newset,oldset)); % throws no error if argument is empty
            end
            function errstr=try_apply(newset,oldset)
                errstr='';
                props=fieldnames(newset);
                newvals=struct2cell(newset);
                oldvals=struct2cell(oldset);
                for i=1:numel(props)
                    try
                        O.cam_obj.(props{i})=newvals{i};
                    catch me
                        errstr=sprintf('%s\n%s',errstr,me.message);
                        O.cam_obj.(props{i})=oldvals{i};
                    end
                end
                if ~isempty(errstr)
                    errstr=sprintf('%s\n\n%s','Some values left unchanged:',errstr);
                end
            end
        end
        
        function edit_output_settings(O,~,source,assignstr)
            switch O.gui_or_udp(source)
                case 'GUI'
                    tmpset.profile_name=['Current (' O.video_profile ')'];
                    tmpset.profile_desc=['Current video settings based on the ' O.video_profile ' profile'];
                    tmpset.VideoWriter=O.vid_obj;
                    O.open_dialog_name='VideoWriterGui';
                    [vidtmp,proftmp]=VideoWriterGui('filename',fullfile(O.vid_obj.Path,O.vid_obj.Filename),'preset',tmpset);
                    O.open_dialog_name='';
                    if ~isempty(vidtmp) % empty if user pressed cancel
                        O.vid_obj=vidtmp;
                        O.video_profile=proftmp;
                        return;
                    end
                case 'UDP'
                    tmpset=propvals(O.vid_obj,'set');
                    tmpset.filename=fullfile(O.vid_obj.Path,O.vid_obj.Filename);
                    tmpset.profile=O.video_profile;
                    if ~exist('assignstr','var') || isempty(assignstr)
                        flds=fieldnames(tmpset);
                        vals=struct2cell(tmpset);
                        msg=sprintf('Assignment string required, for example:\n');
                        for i=1:numel(flds)
                           	if isnumeric(vals{i}) || islogical(vals{i})
                                if ~isempty(vals{i})
                                    valstr=num2str(vals{i});
                                else
                                    valstr='[]';
                                end
                            elseif ischar(vals{i}) || isstring(vals{i})
                                valstr=sprintf('"%s"',vals{i});
                            else
                                valstr=['unsupported datatype: ' class(vals{i})];
                            end
                            msg=sprintf('%s\t%s = %s\n',msg,flds{i},valstr);
                        end
                        O.send_err(msg);
                        return;
                    end
                    tmpset=O.parse_assignment_string(tmpset,assignstr);
                    try
                        vidtmp=VideoWriter(tmpset.filename,tmpset.profile);
                        props=fieldnames(tmpset);
                        for i=1:numel(props)
                            if ~any(strcmpi(props{i},{'filename','profile'}))
                                if ~isempty([vidtmp.(props{i}) tmpset.(props{i})]) % To prevent error of, for example, setting MJ2BitDepth to [] (even though default of MJ2BitDepth is []!!!!! Mathworks...)
                                    if vidtmp.(props{i})~=tmpset.(props{i}) % don't change if same, prevents for example the error 'Setting the CompressionRatio when LosslessCompression is enable is not allowed.'
                                        vidtmp.(props{i})=tmpset.(props{i});
                                    end
                                end
                            end
                        end
                    catch me
                        O.send_err(me.message);
                        return;
                    end
                    delete(O.vid_obj);
                    O.vid_obj=vidtmp;
                    O.video_profile=tmpset.profile;
            end
        end
        
        function grab_frame(O)
            persistent last_size
            if isempty(last_size)
                last_size=[240 320];
            end
            if ~isempty(O.cam_obj) && isvalid(O.cam_obj) && ~O.exit_flag
                try
                    O.frame=O.cam_obj.snapshot;
                    last_size=size(O.frame);
                catch
                    % cam_obj.snapshot will throw a timeout error if a settings
                    % dialog has been open. Catch that error here and set f to
                    % some noise values disp(['grab_frame - ' me.message])
                    O.frame=repmat(randi([0 255],last_size(1:2),'uint8'),1,1,3);
                end
            else
                O.frame=repmat(randi([0 255],last_size(1:2),'uint8'),1,1,3);
            end
            if O.crop_enable && ~all(O.crop_box==[0 0 1 1])
                try
                    res=str2double(regexp(O.cam_obj.Resolution,'x','split'));
                    px=round(O.crop_box.*[res res]);
                    leftx=max(1,min(px(1),res(1)));
                    topy=max(1,min(px(2),res(2)));
                    rightx=max(1,min(px(1)+px(3),res(1)));
                    bottomy=max(1,min(px(2)+px(4),res(2)));
                    O.frame=O.frame(topy:bottomy,leftx:rightx,:);
                catch me
                    if strcmp(me.identifier,'MATLAB:badsubscript')
                        % this happens when the resolution of the cam_obj
                        % increased, res is now larger than the frame which
                        % was grabbed before increase. will be fine next
                        % frame (can't change during recoring so only
                        % preview is interrupted for a frame)
                    else
                        rethrow(me)
                    end
                end
            end
            if O.color_space=='RGB' %#ok<*BDSCA>
                O.frame=O.frame;
            elseif O.color_space=='Grayscale'
                O.frame=repmat(rgb2gray(O.frame),1,1,3);
            elseif O.color_space=='R'
                O.frame(:,:,[2 3])=0;
            elseif O.color_space=='G'
                O.frame(:,:,[1 3])=0;
            elseif O.color_space=='B'
                O.frame(:,:,[1 2])=0;
            else
                error('Unknown colorspace: %s',O.color_space)
            end
            if O.flip_up_down
                O.frame=flipud(O.frame);
            end
            if O.flip_left_right
                O.frame=fliplr(O.frame);
            end
            if O.rotation>0
                O.frame=rot90(O.frame,O.rotation/90);
            end
            if O.rec_frames>0
                O.frame_grab_s(O.rec_frames)=toc(O.rec_start_tic);
                O.rec_frames=O.rec_frames+1;
            end
        end
        
        function show_frame(O)
            if ~all(size(O.display.CData)==size(O.frame))
                overlay_props=propvals(O.overlay,'set');
                % axs_obj hold must be off, consequently the next command
                % will delete all it's children including overlay
                O.display=image(O.axs_obj,[0 1],[0 1],O.frame); % O.axs_obj
                % Adjust aspect ratio of axs_obj so frame isn't stretched
                O.maintain_aspect_ratio;
                % Re-attach the menu to the display
                O.display.UIContextMenu=O.main_menu;
                O.display.Parent.Visible='off';
                % Restore the overlay
                O.build_overlay(overlay_props);
            else
                O.display.CData=O.frame;
            end
            delete(findobj(O.axs_obj.Children,'flat','Tag','redrect'));
            if O.rec_frames>0
                rectangle(O.axs_obj,'Position',[0 0 1 1],'EdgeColor','r','LineWidth',4,'Tag','redrect');
            end
            drawnow limitrate % only update when not done in last 50 ms
        end
        
        function maintain_aspect_ratio(O,~,~)
            % Adjust aspect ratio of axs_obj so frame isn't stretched
            oldUnits=O.axs_obj.Units;
            O.axs_obj.Units='normalized';
            O.axs_obj.Position=[0 0 1 1];
            O.axs_obj.Units='pixels';
            vStretch=O.axs_obj.Position(4)/size(O.frame,1);
            hStretch=O.axs_obj.Position(3)/size(O.frame,2);
            if hStretch>vStretch
                O.axs_obj.Position(3)=O.axs_obj.Position(3)/hStretch*vStretch;
            elseif hStretch<vStretch
                O.axs_obj.Position(4)=O.axs_obj.Position(4)/vStretch*hStretch;
            end
            % Keep centered in figure (automatically resizing doesn't work,
            % tried it. matlab loses track of where the corners are and
            % looks glitchy
            O.axs_obj.Position(1)=(O.fig_obj.Position(3)-O.axs_obj.Position(3))/2;
            O.axs_obj.Position(2)=(O.fig_obj.Position(4)-O.axs_obj.Position(4))/2;
            % Reset the units
            O.axs_obj.Units=oldUnits;
            % Set a time to fit the window to the contect after some time
            O.win_resize_tic=tic;
        end
        
        function resize_figure_to_content(O,~,~)
            if strcmpi(O.fig_obj.WindowState,'maximized')
                return;
            end
            oldUnits=O.axs_obj.Units;
            O.axs_obj.Units='pixels';
            % keep on same center
            O.fig_obj.Position(1)=O.fig_obj.Position(1)+0.5*(O.fig_obj.Position(3)-O.axs_obj.Position(3));
            O.fig_obj.Position(2)=O.fig_obj.Position(2)+0.5*(O.fig_obj.Position(4)-O.axs_obj.Position(4));
            % Make the figure window tight-fitting
            O.fig_obj.Position(3)=O.axs_obj.Position(3);
            O.fig_obj.Position(4)=O.axs_obj.Position(4);
            % Reset the units
            O.axs_obj.Units=oldUnits;
        end
        
        function start_recording(O,~,~)
            try
                open(O.vid_obj);
            catch me
                msg={sprintf('Could not open %s for saving video',O.vid_obj.Filename)};
                msg{end+1}=me.message;
                uiwait(O.big_errordlg(msg,mfilename,'modal'));
                return
            end
            O.fig_obj.Name=[ O.fig_obj.Name ' - Recording to ' O.vid_obj.Filename ];
            O.frame_grab_s=[];
            O.rec_frames=1; % flag *and* counter
            O.build_main_menu; % changed to "stop recording" only when rec_frames>0
            O.rec_start_tic=tic;
            O.last_key_press=[];
        end
        
        function stop_recording(O,~,~)
            was_rec=O.rec_frames>0;
            O.rec_frames=0;
            pause(0.1);
            close(O.vid_obj);
            if was_rec
                % Remove the red border and "recording" from title
                O.show_frame;
                O.fig_obj.Name(regexp(O.fig_obj.Name,' - Rec'):end)=[];
                % Save the timestamps in separate file (I considered
                % storing them coded in the top-left corner pixel of each
                % frame but would only work with no or lossless compression
                [~,fname]=fileparts(O.vid_obj.Filename); % remove the extension
                timestampfile=fullfile(O.vid_obj.Path,[fname '_timestamps.txt']);
                fid = fopen(timestampfile,'wt'); % Write Text mode lest \n doesn't work in Windows
                try
                    fprintf(fid,'%f\n',O.frame_grab_s);
                    fclose(fid);
                catch
                    warning('Could not save timestamp file ''%s''!',timestampfile)
                end
                if O.resample_after_rec
                    pointer=O.fig_obj.Pointer;
                    O.fig_obj.Pointer='watch';
                    delete(O.main_menu);
                    O.main_menu = uicontextmenu;
                    uimenu('Parent',O.main_menu,'Label','Cancel Resampling','Callback',@O.cancel_resample_video);
                    O.display.UIContextMenu=O.main_menu;
                    overlay_props=propvals(O.overlay,'set');
                    src=fullfile(O.vid_obj.Path,O.vid_obj.Filename);
                    tstamps=O.frame_grab_s;
                    fps=O.vid_obj.FrameRate;
                    prof=O.video_profile;
                    opts=propvals(O.vid_obj,'set');
                    resample_video(src,tstamps,fps,prof,'progfun',@O.show_resample_prog,'vidprops',opts);
                    O.build_overlay(overlay_props); % restore overlay to values before resampling changed them
                    O.fig_obj.Pointer=pointer;
                end
            end
            O.build_main_menu;
        end
        
        function cancel_resample_video(O,~,~)
            % simulate double escape press
            O.last_key_press.key='escape-escape';
        end
        
        function save_frame(O)
            try
                writeVideo(O.vid_obj,O.frame)
            catch me
                O.stop_recording;
                msg={sprintf('Error writing to video')};
                msg{end+1}=me.message;
                uiwait(O.big_errordlg(msg,mfilename,'modal'));
                return
            end
        end
        
        function send_msg(O,str)
            if O.udp_obj.Terminator~=13
                error('Terminator must be 13 (\r)');
            end
            str=strip(str); % remove final new line if there is one (shouldnt be one because we add one here, but it's ok, no error needed)
            str(str==O.udp_obj.Terminator)=11; % replace any \r with \n, \r is reserved as the message Terminator character
           % str=strrep(str,'\','\\'); % replace \ with \\ (prints as \)
            % If the message is longer than the output buffer, broadcast
            % in chunks. As of writing I don't expect this to ever happen.
            n_chunks=ceil(numel(str)/(O.udp_obj.OutputBufferSize-1));
            if n_chunks>1
                for i=1:n_chunks-1
                    fprintf(O.udp_obj,sprintf('<Part %d/%d>\r',i,n_chunks),'sync');
                    pause(0.5);
                    fprintf(O.udp_obj,'%s\r',str(1:O.udp_obj.OutputBufferSize-1),'sync');
                    pause(0.5);
                    str(1:O.udp_obj.OutputBufferSize-1)='';
                end
                fprintf(O.udp_obj,sprintf('<Part %d/%d>\r',i,n_chunks),'sync'); % final part
                pause(0.5);
            end
            % Print the remainder of str
            fprintf(O.udp_obj,'%s\r',str,'sync');
            pause(0.5);
        end
        
        function send_err(O,str)
            % str=sprintf('Error: %s',str) ***NOT*** str=['Error: ' str];
            % because that can''t deal with backspaces in the name, it will
            % make the sprintf with send_msg interpreted that as an escape
            % sequence which will give incorrect results or errors
            % depending on the escape sequence used, e.g. anything with
            % C:\Users in it will crash on the \U. But not like this:
            str=sprintf('Error: %s',str);
            O.send_msg(str);
        end
        
        function canceled_by_user=show_resample_prog(O,i,ntotal)
            persistent previous_percent
            if i==1
                O.last_key_press=[];
            end
            now_percent=ceil(i/ntotal*100);
            if i==1 || i==ntotal || now_percent>=previous_percent+1
                percent_str=sprintf('%d%%\n',now_percent);
                O.overlay.String={'Resampling video...',percent_str,'(Cancel in context menu)'};
                previous_percent=now_percent;
            end
            canceled_by_user=~isempty(O.last_key_press) && strcmp(O.last_key_press.key,'escape-escape');
        end
        
        function build_overlay(O,restore_struct)
            % hint: obtain restore_struct using settable_properties(O.overlay)
            delete(O.overlay)
            if ~exist('restore_struct','var') || isempty(restore_struct)
                O.overlay=text(O.axs_obj,0.5,0.5,'','Units','Normalized');
                O.overlay.Color='g';
                O.overlay.FontSize=14;
                O.overlay.FontWeight='bold';
                O.overlay.HorizontalAlignment='center';
            else
                fields=fieldnames(restore_struct);
                values=struct2cell(restore_struct);
                O.overlay=text(O.axs_obj);
                for i=1:numel(fields)
                    O.overlay.(fields{i})=values{i};
                end
            end
        end
        
        function clean_up(O)
            % Clean up
            O.exit_flag=true;
            O.rec_frames=0;
            pause(0.1);
            O.stop_recording;
            if ~isempty(O.udp_obj) && isvalid(O.udp_obj) && strcmpi(O.udp_obj.Status,'open')
                O.send_msg(sprintf('%s on camera %s is closing down. Good-bye.',upper(O.fig_obj.Name),O.cam_obj.Name));
                fclose(O.udp_obj);
            end
            delete(O.cam_obj);
            delete(O.udp_obj);
            clf(O.fig_obj);
            delete(O.fig_obj);
        end
        
        function settings_struct=parse_assignment_string(O,settings_struct,assignstr)
            % if assignstr 'someparameter = 1'
            assign_split_cell=strtrim(strsplit(assignstr,'='));
            % now assignstr is {'someparameter'} {'1'}
            if numel(assign_split_cell)~=2
                error('invalid assignment string: %s',assignstr);
            end
            match=partialMatch(assign_split_cell{1},fieldnames(settings_struct),'IgnoreCase',true);
            if numel(match)==0
                O.send_err(sprintf('assignment field ''%s'' does not match any setting',assign_split_cell{1}));
            elseif numel(match)>1
                O.send_err(sprintf('assignment field ''%s'' matches multiple (%d) settings',assign_split_cell{1},numel(match)));
            end
            settings_struct.(match{1})=eval(assign_split_cell{2});
        end
        function nomstr=gui_or_udp(~,source)
            if isa(source,'matlab.ui.eventdata.ActionData')
                nomstr=categorical({'GUI'});
            elseif ischar(source) && strcmpi(source,'UDP')
                nomstr=categorical({'UDP'});
            else
                error('source should be ActionData (resulting from GUI action) or the string ''UDP''');
            end
        end
        
        function list_commands_callback(O,~,source)
            T=evalc('make_list(O.main_menu,'''')');
            T=regexp(T,'\n','split'); % make cell per line
            T(end)=[]; % remove that final empty string
            switch O.gui_or_udp(source)
                case 'GUI'
                    listdlg('Name','All UDP commands','PromptString','','ListString',T,'SelectionMode','single','ListSize',[250,400],'OKString','Cancel');
                case 'UDP'
                    msg='All commands:';
                    for i=1:numel(T)
                        msg=sprintf('%s\n\tobj.send(''%s'')',msg,T{i});
                    end
                     O.send_msg(msg);
            end
            function make_list(menu,pth)
                % walk through the menu tree and make a list
                % TODO: include the settable parameters in the setting
                % panel like 
                kids=menu.Children;
                for c=numel(kids):-1:1
                    pth{end+1}=kids(c).Label; %#ok<AGROW>
                    if numel(kids(c).Children)>0
                        make_list(kids(c),pth); % recursive
                        pth(end)=[];
                    else
                        str=sprintf('%s > ',pth{:});
                        str(end-2:end)=[]; % remove final ' > '
                        fprintf('%s\n',str); % and add new line
                        pth(end)=[];
                    end
                end
            end
        end
        
    end
    methods (Static)
        function str=onoff(bool)
            if bool
                str='on';
            else
                str='off';
            end
        end
        function efig=big_errordlg(varargin)
            efig=errordlg(varargin{:});
            try
                s=settings;
                msgboxFontSize(efig, s.matlab.fonts.editor.codefont.Size.ActiveValue);
            catch me
                if strcmpi(me.identifier,'MATLAB:UndefinedFunction')
                    warning([mfilename ':no_msgboxFontSize'],'Adam Danz''s msgboxFontSize is not on your path. Download it here to increase the size of fonts in udpcam dialogs.\nhttps://www.mathworks.com/matlabcentral/fileexchange/68460-msgboxfontsize');
                    warning('off',[mfilename ':no_msgboxFontSize']);
                else
                    rethrow(me);
                end
            end
        end
        function O=clear_all_classes_and_instrreset
            % convenience function that resets ALL instruments and clears
            % ALL classes. Note that this includes objects that may have
            % nothing to do with udpcam.
            instrreset;
            clear all classes;
        end
    end
end



