classdef udpcam < handle
    
    properties (Access=private)
        udp_settings
        udp_obj
        fig_obj
        axs_obj
        cam_obj
        vid_obj
        exit_flag=false
        rec_frames=0 % Dual purpose flow-control flag AND counter for frame_grab_s array
        mainMenu
        display
        frame
        rec_start_tic
        last_key_press
        frame_grab_s
        video_profile
        overlay
        win_resize_tic % timer since last window resize
        color_space;
        resample_after_rec; % make video realtime after recording
    end
    
    methods (Access=public)
        function O=udpcam(varargin)
            p=inputParser;
            p.addParameter('IP','127.0.0.1',@ischar);
            p.addParameter('LocalPort',4010,@(x)isnumeric(x) && mod(x,1)==0 && x>=1024 && x<=49151);
            p.addParameter('RemotePort',4011,@(x)isnumeric(x) && mod(x,1)==0 && x>=1024 && x<=49151);
            p.addParameter('position',[260 500 640 480],@(x)isnumeric(x)&&isvector(x)&&numel(x)==4);
            p.addParameter('center',true,@(x)any(x==[1 0]));
            p.addParameter('bgcolor',[0.5 0.5 0.5],@(x)isnumeric(x)&&numel(x)==3&&all(x>=0&&x<=1));
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
            O.resample_after_rec = true;
            
            % Setup the window
            O.fig_obj=figure;
            O.fig_obj.Position=p.Results.position;
            O.fig_obj.Color=p.Results.bgcolor;
            O.fig_obj.Visible='off';
            O.fig_obj.Units='Pixels';
            O.fig_obj.CloseRequestFcn=@O.close_button_callback;
            O.fig_obj.ResizeFcn=@O.maintain_aspect_ratio;
            set(O.fig_obj,'pointer','watch');
            O.fig_obj.NumberTitle='Off';
            O.fig_obj.MenuBar='none';
            O.fig_obj.ToolBar='none';
            O.fig_obj.Name = [mfilename ' ' p.Results.IP ':' num2str(p.Results.LocalPort)];
            O.fig_obj.WindowKeyPressFcn=@O.key_press_callback;
            
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
                    uiwait(errordlg(me.message,mfilename,'modal'));
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
                msg{end+1}='Tip: run instrreset to release all connections';
                uiwait(errordlg(msg,mfilename,'modal'));
                O.clean_up;
                delete(O);
                return
            end
            
            % Create the main right-click context menu
            O.build_main_menu;
            
            % Start the loop
            O.main_loop;
            O.clean_up;
            delete(O);
        end
    end
    methods (Access=private)
        function main_loop(O)
            set(O.fig_obj, 'pointer', 'arrow');
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
            pause(1/4); % give plenty time to finish current cycle of the main_loop
            %   O.clean_up;
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
            fopen(O.udp_obj);
            O.hello_callback
        end
        
        function parse_udp_message(O,~,~)
            % First thing, let remote control know their message was received
            fprintf(O.udp_obj,'Roger');
            % Parse the message
            msg=strtrim(fscanf(O.udp_obj));
            commands=cellfun(@strtrim,regexp(msg,'>','split'),'UniformOutput',false); % 'Color Space > RGB' --> {'Color Space'}    {'RGB'}
            currentmenu=O.mainMenu;
            for i=1:numel(commands)
                labels={currentmenu.Children.Label};
                match=partialMatch(commands{i},labels,'IgnoreCase',true,'FullMatchPrecedence',true);
                if numel(match)~=1
                    fprintf(O.udp_obj,sprintf('No (partial) match for ''%s''',commands{i}));
                    return
                elseif numel(match)>1
                    fprintf(O.udp_obj,sprintf('Multiple (%d) matches for ''%s''',numel(match),commands{i}));
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
                elseif numel(commands)==i+1 % there is a remaining commands
                    feval(currentmenu.MenuSelectedFcn,currentmenu,'UDP',commands{i+1});
                elseif numel(commands)>i+1 % there are more than 1 remaining commands
                    fprintf(O.udp_obj,sprintf('Too many commands after %s>',commands{i}));
                end
            catch me
                fprintf(O.udp_obj,me.message);
            end
        end
        
        function list_commands_callback(O,~,source)
            T=evalc('make_list(O.mainMenu,'''')');
            T=regexp(T,'\n','split'); % make cell per line
            T(end)=[]; % empty string
            switch O.kindof(source)
                case 'GUI'
                    listdlg('Name','All UDP commands','PromptString','','ListString',T,'SelectionMode','single','ListSize',[250,400],'OKString','Cancel');
                case 'UDP'
                    fprintf(O.udp_obj,'All commands:')
                    for i=1:numel(T)
                        fprintf(O.udp_obj,sprintf('--- %s',T{i}))
                    end
            end
            function make_list(menu,pth)
                kids=menu.Children;
                for c=numel(kids):-1:1
                    pth{end+1}=kids(c).Label;
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
        

            
        function O=build_main_menu(O)
            delete(O.mainMenu);
            O.mainMenu = uicontextmenu;
            if ~O.rec_frames>0
                uimenu('Parent',O.mainMenu,'Label','UDP');
                uimenu('Parent',O.mainMenu,'Label','Camera');
                uimenu('Parent',O.mainMenu,'Label','Output');
                uimenu('Parent',O.mainMenu,'Label','Record','Separator','on','Callback',@O.start_recording);
                uimenu('Parent',O.mainMenu,'Label','Quit','Separator','on','Callback',@O.close_button_callback);
                O.build_udp_menu;
                O.build_camera_menu;
                O.build_output_menu;
            else
                uimenu('Parent',O.mainMenu,'Label','Stop Recording','Callback',@O.stop_recording);
            end
            % Attach the menu to the display
            O.display.UIContextMenu=O.mainMenu;
        end
        
        function build_udp_menu(O,~,~)
            udpmenu=findobj(O.mainMenu.Children,'flat','Label','UDP');
            delete(udpmenu.Children);
            uimenu('Parent',udpmenu,'Label','Settings...','Callback',@O.edit_udp_connection);
            uimenu('Parent',udpmenu,'Label','Hello','Callback',@(src,evt)hello_callback(O,src,evt));
            uimenu('Parent',udpmenu,'Label','List commands','Callback',@(src,evt)O.list_commands_callback(src,evt));
        end
        
        function hello_callback(O,a,b)
            fprintf(O.udp_obj,sprintf('Hi, this is %s using camera %s\n',O.fig_obj.Name,O.cam_obj.Name));
        end
        
        function build_camera_menu(O,~,~)
            cameraMenu=findobj(O.mainMenu.Children,'flat','Label','Camera');
            delete(cameraMenu.Children);
            selectMenu=uimenu('Parent',cameraMenu,'Label','Select');
            cams=[webcamlist 'None'];
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
            outMenu=findobj(O.mainMenu.Children,'flat','Label','Output');
            delete(outMenu.Children);
            uimenu('Parent',outMenu,'Label','VideoWriter...','Callback',@O.edit_output_settings);
            uimenu('Parent',outMenu,'Label','Resample','Checked',O.onoff(O.resample_after_rec),'Callback',@O.toggle_resample);
        end
        
        function select_camera(O,src,~)
            cameraName=src.Text;
            set(src.Parent.Children,'Checked','off');
            src.Checked='on';
            delete(O.cam_obj);
            if strcmpi(cameraName,'None')
                O.build_camera_menu;
            else
                % select the cam_obj
                try
                    O.cam_obj=webcam(cameraName);
                catch me
                    disp(['select_camera - ' me.message]);
                    return
                end
                % Add dynamic menus to cam_obj menu (depending on
                % availability of a cam_obj and its make and model)
                cameraMenu=findobj(O.mainMenu.Children,'flat','Label','Camera');
                % - Add the Resolution menu
                resos=O.cam_obj.AvailableResolutions;
                [~,idx]=sort(cellfun(@(x)prod(cellfun(@str2double,regexp(x,'x','split'))),resos),'descend'); % order resos by ...
                resos=resos(idx);                                                                         % ... number of pixels
                delete(findobj(cameraMenu.Children,'flat','Label','Resolution'));
                resMenu=uimenu('Parent',cameraMenu,'Label','Resolution');
                for i=1:numel(resos)
                    uimenu('Parent',resMenu,'Label',resos{i},'Callback',@(src,evt)O.select_resolution(src,evt));
                end
                set(findobj(resMenu.Children,'flat','Label',O.cam_obj.Resolution),'Checked','on');
                % - Add the color-space selection menu
                spaces={'RGB','Grayscale','R','G','B'};
                delete(findobj(cameraMenu.Children,'flat','Label','Color Space'));
                colorMenu=uimenu('Parent',cameraMenu,'Label','Color Space');
                for i=1:numel(spaces)
                    uimenu('Parent',colorMenu,'Label',spaces{i},'Callback',@O.select_color);
                end
                set(findobj(colorMenu.Children,'flat','Label',O.color_space),'Checked','on')
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
        
        function select_color(O,src,~)
            set(src.Parent.Children,'Checked','off');
            src.Checked='on';
            O.color_space=categorical({src.Text}); 
        end
        
        function toggle_resample(O,src,~)
            O.resample_after_rec=~O.resample_after_rec;
            src.Checked=O.onoff(O.resample_after_rec);
        end
        
        function edit_udp_connection(O,~,source,assignstr)
            tmpset=O.udp_settings;
            switch O.kindof(source)
                case 'GUI'
                    while true
                        tit='UDP Settings';
                        tit(end+1:end+42-numel(tit))=' ';
                        [tmpset,pressedOk]=guisetstruct(tmpset,tit,8);
                        if ~pressedOk
                            return; % user changed their mind, no changes will be made
                        end
                        errstr=check_for_errors(tmpset);
                        if ~isempty(errstr)
                            uiwait(errordlg(strsplit(errstr,'\n'),mfilename,'modal'));
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
        
        function edit_output_settings(O,~,source,assignstr)
            %  tmpset=O.video_settings;
            switch O.kindof(source)
                case 'GUI'
                    tmpset.profile_name=['Current (' O.video_profile ')'];
                    tmpset.profile_desc=['Current video settings based on the ' O.video_profile ' profile'];
                    tmpset.VideoWriter=O.vid_obj;
                    [vidtmp,proftmp]=VideoWriterGui('filename',fullfile(O.vid_obj.Path,O.vid_obj.Filename),'preset',tmpset);
                    if ~isempty(vidtmp)
                        O.vid_obj=vidtmp;
                        O.video_profile=proftmp;
                        return;
                    end
                case 'UDP'
                    tmpset=propvals(O.vid_obj,'set');
                    tmpset.filename=fullfile(O.vid_obj.Path,O.vid_obj.Filename);
                    tmpset.profile=O.video_profile;
                    if ~exist('assignstr','var')
                        fprintf(O.udp_obj,'Assignment string required, for example:');
                        flds=fieldnames(tmpset);
                        vals=struct2cell(tmpset);
                        for i=1:numel(flds)
                            valstr=strtrim(evalc('disp(vals{i})'));
                            if isempty(valstr)
                                valstr='[]';
                            end
                            fprintf(O.udp_obj,sprintf('--- %s = %s',flds{i},valstr));
                        end
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
                        fprintf(O.udp_obj,me.message);
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
                O.display.UIContextMenu=O.mainMenu;
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
            % but only if the resizing isn't to either the full screen
            % height or width, like when expanded to the max in windows.
            % 666 This doesn't work entirely because scaling to the max is
            % only to where the taskbar is in windows. And I don't know how
            % this works on Linux or Mac. But for now good enough
            scrwidhei=get(0,'screensize');
            scrwidhei(1:2)=[]; % remove x and y pos
            if ~any(O.fig_obj.Position([3 4])==scrwidhei)
                O.win_resize_tic=tic;
            end
        end
        
        function resize_figure_to_content(O,~,~)
            oldUnits=O.axs_obj.Units;
            O.axs_obj.Units='pixels';
            % keep on same center
            O.fig_obj.Position(1)=O.fig_obj.Position(1)+0.5*(O.fig_obj.Position(3)-O.axs_obj.Position(3));
            O.fig_obj.Position(2)=O.fig_obj.Position(2)+0.5*(O.fig_obj.Position(4)-O.axs_obj.Position(4));
            % Make the figure window tight fitting
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
                uiwait(errordlg(msg,mfilename,'modal'));
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
                % Save the timestamps in separate file (considered storing
                % them in top-left corner pixel of each frame but would
                % only work with no or lossless compression
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
                    overlay_props=propvals(O.overlay,'set');
                    src=fullfile(O.vid_obj.Path,O.vid_obj.Filename);
                    tstamps=O.frame_grab_s;
                    fps=O.vid_obj.FrameRate;
                    prof=O.video_profile;
                    opts=propvals(O.vid_obj,'set');
                    resample_video(src,tstamps,fps,prof,'progfun',@O.show_resample_prog,'vidprops',opts);
                    O.build_overlay(overlay_props); % restore overlay to values before resampling changed them
                end
            end
            O.build_main_menu;
        end
        
        function save_frame(O)
            try
                writeVideo(O.vid_obj,O.frame)
            catch me
                O.stop_recording;
                msg={sprintf('Error writing to video')};
                msg{end+1}=me.message;
                uiwait(errordlg(msg,mfilename,'modal'));
                return
            end
        end
        
        function canceled_by_user=show_resample_prog(O,i,ntotal)
            persistent previous_percent
            if i==1
                O.last_key_press=[];
            end
            now_percent=ceil(i/ntotal*100);
            if i==1 || i==ntotal || now_percent>=previous_percent+1
                percent_str=sprintf('%d%%\n',now_percent);
                O.overlay.String={'Resampling video...',percent_str};
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
                fprintf(O.udp_obj,'bye');
                fclose(O.udp_obj);
            end
            delete(O.cam_obj);
            delete(O.udp_obj);
            delete(O.fig_obj);
        end
    end
    
    methods (Static)
        function settings_struct=parse_assignment_string(settings_struct,assignstr)
            % if assignstr 'someparameter = 1'
            assignstr=strtrim(strsplit(assignstr,'='));
            % now assignstr is {'someparameter'} {'1'}
            if numel(assignstr)~=2
                error('invalid assignment string: %s',assignstr);
            end
            match=partialMatch(assignstr{1},fieldnames(settings_struct));
            if numel(match)==0
                error('assignment field ''%s'' does not match any setting',assignstr{1});
            elseif numel(match)>1
                error('assignment field ''%s'' matches multiple (%d) settings',assignstr{1},numel(match));
            end
            settings_struct.(match{1})=eval(assignstr{2});
        end
        function nomstr=kindof(source)
            if isa(source,'matlab.ui.eventdata.ActionData')
                nomstr=categorical({'GUI'});
            elseif ischar(source) && strcmpi(source,'UDP')
                nomstr=categorical({'UDP'});
            else
                error('source should be ActionData (resulting from GUI action) or the string ''UDP''');
            end
        end
        function str=onoff(bool)
            if bool
                str='on';
            else
                str='off';
            end
        end
    end
end




