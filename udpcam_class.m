classdef udpcam_class < handle
    
    properties (Access=public)
        udp_settings
        udp_connection
        win
        camera
        shutting_down=false;
        recording=false;
        mainMenu
        display
        frame
    end
    
    methods (Access=public)
        function O=udpcam_class(varargin)
            p=inputParser;
            p.addParameter('IP','127.0.0.1',@ischar);
            p.addParameter('LocalPort',4010,@(x)mod(x,1)==0 && x>=1024 && x<=49151);
            p.addParameter('RemotePort',4011,@isnumeric);
            p.addParameter('position',[260 500 640 480],@(x)isnumeric(x)&&isvector(x)&&numel(x)==4);
            p.addParameter('center',true,@(x)any(x==[1 0]));
            p.parse(varargin{:});
            
            % Set up the UDP connection for receiving commands
            O.udp_settings.enable=true;
            O.udp_settings.remotehost=p.Results.IP;
            O.udp_settings.localport=p.Results.LocalPort;
            O.udp_settings.remoteport=p.Results.RemotePort;
            O.setup_udp_connection;
            
            O.win=figure('Position',p.Results.position,'Visible','off','Units','Pixels' ...
                ,'CloseRequestFcn',@O.close_button_callback); %  ,'KeyPressFcn',@(src,evnt)onKey(evnt)
            if p.Results.center
                movegui(O.win,'center')
            end
            hAx = axes('Units','normalized','Position',[0 0 1 1],'box','on');
            % Initialize the UI.
            O.win.NumberTitle='Off';
            O.win.MenuBar='none';
            O.win.ToolBar='none';
            % Set the title of the figure
            O.win.Name = [mfilename ' ' p.Results.IP ':' num2str(p.Results.LocalPort)];
            % Make the window visible.
            O.win.Visible = 'on';
            
            % The camera object
            if ~isempty(webcamlist)
                O.camera=webcam;
            else
                O.camera=[];
            end
            
            O.shutting_down=false;
            O.recording=false;
            
            % Initialize the display window
            O.display=image(hAx,zeros(1,1,3)); % 1 pixel RGB image to initialize
            % Create the main right-click context menu
            buildMainMenu(O);
            
            
            %try
            O.main_loop;
            %catch
            %end
            O.clean_up;
            delete(O);
        end
    end
    methods (Access=private)
        function main_loop(O)
            while ~O.shutting_down && isvalid(O.win)
                ttt=tic;
                O.grab_frame;
                O.show_frame;
                pause(1/20-toc(ttt))
            end
        end
        
        function close_button_callback(O,~,~)
            set(O.win, 'pointer', 'watch')
            O.shutting_down=true; % breaks the video loop and makes that uiwait is skipped after coming out of video loop
            pause(1/3); % give plenty time to finish current cycle of the main_loop
         %   O.clean_up;
        end
        
        function setup_udp_connection(O)
            if ~isempty(O.udp_connection)
                fclose(O.udp_connection);
                delete(O.udp_connection)
                O.udp_connection=[];
            end
            try
                O.udp_connection=udp(O.udp_settings.remotehost,'RemotePort',O.udp_settings.remoteport,'LocalPort',O.udp_settings.localport);
                O.udp_connection.DatagramReceivedFcn = @parse_message;
                fopen(O.udp_connection);
                fprintf(O.udp_connection,'%s online',mfilename);
            catch me
                uiwait(errordlg(me.message,mfilename,'modal'));
            end
        end
        
        function O=buildMainMenu(O)
            delete(O.mainMenu);
            O.mainMenu = uicontextmenu;
            if ~O.recording
                uimenu('Parent',O.mainMenu,'Label','UDP Settings...','Callback',@O.edit_udp_connection);
                uimenu('Parent',O.mainMenu,'Label','Camera');
                uimenu('Parent',O.mainMenu,'Label','Output');
                uimenu('Parent',O.mainMenu,'Label','Record','Callback',@O.start_recording);
                O.build_camera_menu;
                O.build_output_menu;
            else
                uimenu('Parent',O.mainMenu,'Label','Stop recording','Callback',@O.stop_recording);
            end
            % Attach the menu to the display
            O.display.UIContextMenu=O.mainMenu;
        end
        
        function build_camera_menu(O,~,~)
            cameraMenu=findobj(O.mainMenu.Children,'flat','Label','Camera');
            delete(cameraMenu.Children);
            selectMenu=uimenu('Parent',cameraMenu,'Label','Select');
            cams=[webcamlist 'None'];
            for i=1:numel(cams)
                uimenu('Parent',selectMenu,'Label',cams{i},'Callback',@(src,evt)O.camera_select(src,evt));
            end
            uimenu('Parent',selectMenu,'Label','Refresh List','Callback',@O.build_camera_menu);
            if ~isempty(O.camera) && isvalid(O.camera)
                O.camera_select(findobj(selectMenu.Children,'flat','Label',O.camera.Name));
            else
                set(findobj(selectMenu.Children,'flat','Label','None'),'Checked','on')
            end
        end
        
         function build_output_menu(O,~,~)
            outMenu=findobj(O.mainMenu.Children,'flat','Label','Output');
            delete(outMenu.Children);
            selectMenu=uimenu('Parent',outMenu,'Label','Select');
            cams=[webcamlist 'None'];
            for i=1:numel(cams)
                uimenu('Parent',selectMenu,'Label',cams{i},'Callback',@(src,evt)O.camera_select(src,evt));
            end
            uimenu('Parent',selectMenu,'Label','Refresh List','Callback',@O.build_camera_menu);
            if ~isempty(O.camera) && isvalid(O.camera)
                O.camera_select(findobj(selectMenu.Children,'flat','Label',O.camera.Name));
            else
                set(findobj(selectMenu.Children,'flat','Label','None'),'Checked','on')
            end
        end
        
        function camera_select(O,src,~)
            cameraName=src.Text;
            set(src.Parent.Children,'Checked','off');
            src.Checked='on';
            delete(O.camera);
            if strcmpi(cameraName,'None')
                O.build_camera_menu;
            else
                % select the camera
                try
                    O.camera=webcam(cameraName);
                catch me
                    disp(['camera_select - ' me.message]);
                    return
                end
                % Add dynamic menus to camera menu (depending on
                % availability of a camera and its make and model)
                cameraMenu=findobj(O.mainMenu.Children,'flat','Label','Camera');
                % - Add the Resolution menu
                resos=O.camera.AvailableResolutions;
                [~,idx]=sort(cellfun(@(x)prod(cellfun(@str2double,regexp(x,'x','split'))),resos),'descend'); % order resos by ...
                resos=resos(idx);                                                                         % ... number of pixels
                delete(findobj(cameraMenu.Children,'flat','Label','Resolution'));
                resMenu=uimenu('Parent',cameraMenu,'Label','Resolution');
                for i=1:numel(resos)
                    uimenu('Parent',resMenu,'Label',resos{i},'Callback',@(src,evt)O.resolution_select(src,evt));
                end
                set(findobj(resMenu.Children,'flat','Label',O.camera.Resolution),'Checked','on');
                % - Add the color-space selection menu
                spaces={'RGB','Grayscale','R','G','B'};
                delete(findobj(cameraMenu.Children,'flat','Label','Color Space'));
                colorMenu=uimenu('Parent',cameraMenu,'Label','Color Space');
                for i=1:numel(spaces)
                    uimenu('Parent',colorMenu,'Label',spaces{i},'Callback',@O.color_select);
                end
                set(findobj(colorMenu.Children,'flat','Label',spaces{1}),'Checked','on')
            end
        end
        
        function O=resolution_select(O,src,~)
            if ~isempty(O.camera) && isvalid(O.camera)
                O.camera.Resolution=src.Text;
                %O.grab_frame; % to flush possibly lingering frame of previous resolution
                set(src.Parent.Children,'Checked','off');
                src.Checked='on';
            end
        end
        
        function color_select(O,src,~)
            set(src.Parent.Children,'Checked','off');
            src.Checked='on';
        end
        
        function grab_frame(O)
            if ~isempty(O.camera) && isvalid(O.camera) && ~O.shutting_down
                try
                    O.frame=O.camera.snapshot;
                catch me
                    % camera.snapshot will throw a timeout error if a settings
                    % dialog has been open. Catch that error here and set f to
                    % some value
                    disp(['grab_frame - ' me.message])
                    O.frame=repmat(realsqrt(rand(525,700)),1,1,3);
                end
            else
                O.frame=repmat(realsqrt(rand(525,700)),1,1,3);
            end
            color_space = nominal(O.get_color_space(O.mainMenu));
            if color_space=='RGB'
                O.frame=O.frame;
            elseif color_space=='Grayscale'
                O.frame=repmat(rgb2gray(O.frame),1,1,3);
            elseif color_space=='R'
                O.frame(:,:,[2 3])=0;
            elseif color_space=='G'
                O.frame(:,:,[1 3])=0;
            elseif color_space=='B'
                O.frame(:,:,[1 2])=0;
            else
                error('Unknown colorspace: %s',color_space)
            end
        end
        
        function show_frame(O)
            if ~all(size(O.display.CData)==size(O.frame))
                O.display=image(O.display.Parent,O.frame);
                % Re-attach the menu to the display
                O.display.UIContextMenu=O.mainMenu;
                set(O.display.Parent,'XTick','','YTick','','box','on');
            else
                O.display.CData=O.frame;
            end
        end

        function start_recording(O,~,~)
            O.recording=true;
            O.buildMainMenu;
        end
        
        function stop_recording(O,~,~)
            O.recording=false;
            O.buildMainMenu;
        end
  
        function clean_up(O)
            % Clean up
            if ~isempty(O.udp_connection) && isvalid(O.udp_connection)
                fclose(O.udp_connection);
            end
            delete(O.udp_connection);
            delete(O.camera);
            delete(O.win);
        end
    end
    
    methods (Static)
        function str = get_color_space(mainMenu)
            try
                colmenu=findobj(mainMenu.Children,'Label','Color Space');
                if isempty(colmenu)
                    str='RGB';
                else
                    check_item=findobj(colmenu.Children,'flat','Checked','on');
                    str=check_item.Text; % e.g. 'Grayscale'
                end
            catch me
                disp(['get_color_space - ' me.message]);
                str='RGB';
            end
        end
    end
end




