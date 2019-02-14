classdef VideoWriterGui < handle
    
    properties (GetAccess=public,SetAccess=private)
        vid_obj
    end
    properties (Access=private)
        fig_obj
        prof_info
    end
    methods
        function [O,vid_obj]=VideoWriterGui(filename,profile,varargin)
            % Load the information about available profiles
            import('audiovideo.internal.writer.profile.ProfileFactory');
            O.prof_info=ProfileFactory.getKnownProfiles;
            
            if ~exist('filename','var') || isempty(filename)
                filename=fullfile(pwd,['video_' datestr(now,'YYYYMMDD_hhmmss')]);
            elseif ~ischar(filename)
                error('arg #1 (filename) must be empty or a string');
            end
            if ~exist('profile','var') || isempty(profile)
                profile=O.prof_info(1).Name;
            elseif ~ischar(profile) || ~any(strcmpi(x,{O.prof_info(:).Name}))
                error('arg #2 (profile) must be empty or one of the following strings:\n %s',sprintf('\t''%s''\n',O.prof_info(:).Name));
            end
            p=inputParser;
            p.addParameter('position',[260 500 400 120],@(x)isnumeric(x)&&isvector(x)&&numel(x)==4);
            p.addParameter('center',true,@(x)any(x==[1 0]));
            p.parse(varargin{:});
            
            % Create the main window
            O.fig_obj=figure;
            O.fig_obj.Position=p.Results.position;
            O.fig_obj.Visible='off';
            O.fig_obj.Units='Pixels';
            O.fig_obj.CloseRequestFcn=@O.close_button_callback;
            O.fig_obj.ResizeFcn=[];
            O.fig_obj.NumberTitle='Off';
            O.fig_obj.MenuBar='none';
            O.fig_obj.ToolBar='none';
            O.fig_obj.Name = mfilename;
            % Put at center of screen if requested
            if p.Results.center
                movegui(O.fig_obj,'center')
            end
            
            % Add the static GUI elements
            O.build_gui(filename,profile)
            % Make the window visible.
            fig_obj.Visible = 'on';
            drawnow;
            uiwait(O.fig_obj);
            vid_obj=O.vid_obj;
            delete(O);
        end
        
        function build_gui(O,filename,profile)
            % all dimension in pixels
            lblw=60;
            hei=18;
            vspace=12;
            hspace=10;
            row=hei+vspace;
            top=10;
            left=10;
            
            % Determine the number of rows in the gui
            n_rows=3;
            % set the window height accordingly
            fig_hei=n_rows*(row+vspace);
            O.fig_obj.Position(4)=fig_hei;
            % Add file search button
            filebut=uicontrol('Parent',O.fig_obj,'Style','pushbutton','String','File');
            filebut.Tag='filebut';
            filebut.Position=[left fig_hei-1*row lblw hei];
            filebut.Callback=@O.filebut_callback;
            if exist('filename','var')
                filebut.TooltipString=filename;
            end
            % Add profile pop up menu
            profpop=uicontrol('Parent',O.fig_obj,'Style','popup');
            profpop.String={O.prof_info(:).Name};
            profpop.Tag='profpop';
            if exist('profile','var')
                profpop.Value=find(strcmpi(profile,{O.prof_info(:).Name}));
            end
            profpop.Position=[left+lblw+hspace fig_hei-row 140 hei];
            profpop.Callback=@O.profpop_callback;
            profpop.TooltipString='';
            profpop.Callback=@O.profpop_callback;
            profpop.ButtonDownFcn=@O.profpop_callback;
            O.profpop_callback;
            
            % vid_obj=VideoWriter(filebut.TooltipString,profpop.String{profpop.Value});
            
            
            
            % Add Cancel button
            cancelbut=uicontrol('Parent',O.fig_obj,'Style','pushbutton','String','Cancel');
            cancelbut.Tag='cancelbut';
            cancelbut.Position=[left fig_hei-2*row lblw hei];
            cancelbut.Callback=@O.cancelbut_callback;
            % Add OK button
            okbut=uicontrol('Parent',O.fig_obj,'Style','pushbutton','String','OK');
            okbut.Tag='okbut';
            okbut.Position=[left+lblw+hspace fig_hei-2*row lblw hei];
            okbut.Callback=@O.okbut_callback;
            
            % Apply style to all elements
            %style={'BackgroundColor',fig_obj.Color,'FontSize',10};
            style={'FontSize',10};
            ui_elements=findobj(O.fig_obj.Children,'Type','UIControl');
            for i=1:numel(ui_elements)
                set(ui_elements(i),style{:});
            end
        end
        function okbut_callback(O,~,~)
            filebut=findobj(O.fig_obj,'Tag','filebut');
            profpop=findobj(O.fig_obj,'Tag','profpop');
            try
                O.vid_obj=VideoWriter(filebut.TooltipString,profpop.String{profpop.Value});
            catch me
                uiwait(errordlg(me.message,mfilename,'modal'));
                return;
            end
            delete(O.fig_obj);
        end
        function cancelbut_callback(O,~,~)
            O.vid_obj=[];
            delete(O.fig_obj);
        end
        function close_button_callback(O,~,~)
            O.cancelbut_callback;
        end
        
        function profpop_callback(O,~,~)
            profpop=findobj(O.fig_obj,'Tag','profpop');
            profpop.TooltipString=O.prof_info(profpop.Value).Description;
            % change the extension of the filename to the selected profile
            filebut=findobj(O.fig_obj,'Tag','filebut');
            [fld,nme]=fileparts(filebut.TooltipString);
            ext=[O.prof_info(:).FileExtensions];
            fname=fullfile(fld,nme);
            filebut.TooltipString=[fname ext{profpop.Value}];
          % O.build_gui
        end
        function filebut_callback(O,~,~)
            filebut=findobj(O.fig_obj,'Tag','filebut');
            % Make the filters (movie extensions)
            ext=[O.prof_info(:).FileExtensions];
            unique_ext=unique(ext);
            filters{1,1}=strtrim(sprintf('*%s; ',unique_ext{:}));
            filters{1,2}=['MATLAB movie formats (' strtrim(sprintf('*%s, ',unique_ext{:})) ')'];
            filters{1,2}(end-1)=[]; % remove final comma
            filters{2,1}='*.*';
            filters{2,2}='All Files (*.*)';
            % Make the default name (with extension matching the selected profile)
            %  [fld,nme]=fileparts(obj.TooltipString);
            %  fname=fullfile(fld,nme);
            %  if get(findobj(obj.Parent,'Tag','profpop'),'Value')>1
            %      fname=[fname ext{get(findobj(obj.Parent,'Tag','profpop'),'Value')}];
            %  end
            [file,folder]=uiputfile(filters,'Save movie as',filebut.TooltipString);
            if isnumeric(file)
                % user pressed cancel
                return;
            end
            filebut.TooltipString=fullfile(folder,file);
        end
    end
end

