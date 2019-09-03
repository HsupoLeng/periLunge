function [feat_probs, feat_prob_edges, featAll] = FeaturesAfterLunge(flymat_name, common_path, feat_name, num_frames, check_attacked_fly, genotypes, selected_genotype, hist_stat)
    load(fullfile(common_path, flymat_name));
    featAll = struct('movie', '', 'fly', nan);

    if ~isempty(genotypes) % To look at pairing of specific genotypes, use, for example, [10,11] or [90, 1]; otherwise, [].
        all_genotypes = [flymatAll(:).genotype];
        flymatAll_mask_cell = arrayfun(@(type) all_genotypes == type, genotypes, 'UniformOutput', false);
        flymatAll_mask = any(vertcat(flymatAll_mask_cell{:}));
        flymatAll = flymatAll(flymatAll_mask);
    end
    
    featAll_sz = 0;
    for i = 1:length(flymatAll)
        % Allow mixed pairing. Use selected_genotype to indicate the
        % genotype that you want to examine in a pair
        if isempty(selected_genotype)
            selected_genotype = genotypes;
        end
        if ~ismember(flymatAll(i).genotype, selected_genotype) 
            continue; 
        end
        
        movie = flymatAll(i).movie{1};
        fly_feature = flymatAll(i).fly; % Take feature value from fly_feature
        another_fly_in_pair = fly_feature + (-1)^(mod(fly_feature, 2)+1);
        if check_attacked_fly % If we are interested in the feature of the attacked fly
            fly_time = another_fly_in_pair; 
        else
            fly_time = fly_feature; 
        end
        
        fly_time_idx = find(bitand(strcmp([flymatAll(:).movie], movie), [flymatAll(:).fly] == fly_time)); 
        LungeStarts = flymatAll(fly_time_idx).L_startsm;
        LungeEnds = flymatAll(fly_time_idx).L_endsm;
        
        entering_frame_30_min = min(flymatAll([fly_feature, another_fly_in_pair]).EnteringFrame);
        ending_frame_30_min = entering_frame_30_min + flymatAll(fly_feature).ThirtyMinFrame; 
        lunge_starts_mask = bitand(LungeStarts >= entering_frame_30_min, LungeStarts < ending_frame_30_min);
        lunge_ends_mask = bitand(LungeEnds >= entering_frame_30_min, LungeEnds < ending_frame_30_min);
        lunge_joint_mask = bitand(lunge_starts_mask, lunge_ends_mask);
        LungeStarts = LungeStarts(lunge_joint_mask);
        LungeEnds = LungeEnds(lunge_joint_mask);

        file_path = fullfile(common_path, movie(1:6), movie, movie);
        feat_mat_name = fullfile(file_path, strcat(movie, '-feat.mat'));

        try
            load(feat_mat_name);
        catch ME
            movie_parts = strsplit(movie, {'-', '_'});
            cwd_contents = dir(common_path);
            cwd_subfolders = {cwd_contents([cwd_contents(:).isdir]).name};
            target_subfolder = cwd_subfolders(contains(cwd_subfolders, movie_parts{1}));
            file_path = fullfile(common_path, target_subfolder{1}, movie, movie);
            feat_mat_name = fullfile(file_path, strcat(movie, '-feat.mat'));
            load(feat_mat_name);
        end
        total_num_frame = size(feat.data, 2);
        if num_frames > 0
            LungeStarts(abs(LungeEnds - total_num_frame) < num_frames) = [];
            LungeEnds(abs(LungeEnds - total_num_frame) < num_frames) = []; 
        else
            LungeEnds(LungeStarts < abs(num_frames)) = [];
            LungeStarts(LungeStarts < abs(num_frames)) = [];
        end
        
        featAll_sz = featAll_sz + 1;
        featAll(featAll_sz).lunge_starts = LungeStarts';
        featAll(featAll_sz).lunge_ends = LungeEnds';
        
        mask_cell = cell(length(feat_name), 1);
        for j=1:length(feat_name)
            feature_str_components = strsplit(feat_name{j}, '_');
            feature_str_core = feature_str_components{1};
            mask_cell{j} = ~cellfun(@isempty, regexp(feat.names, strcat('^', feature_str_core)));
            cnt = 1;
            while sum(mask_cell{j}) > 1
                feature_str_core = strjoin({feature_str_core, feature_str_components{cnt + 1}}, '_');
                mask_cell{j} = ~cellfun(@isempty, regexp(feat.names, strcat('^', feature_str_core)));
                cnt = cnt + 1;
            end
        end
        
        featAll(featAll_sz).movie = movie; 
        featAll(featAll_sz).fly = fly_feature;
        featAll(featAll_sz).genotype = flymatAll(fly_feature).genotype; 
        feat_vals = zeros(length(LungeStarts), abs(num_frames));

        for j=1:length(feat_name)
            if strcmp(feat_name{j}, 'facing_angle_mutual_other')
                if mod(fly_time, 2)
                    fly_feature = fly_time + 1; % Take lunge times from fly_time
                else
                    fly_feature = fly_time - 1; 
                end
            end
            for k=1:length(LungeStarts)
                if num_frames > 0 
                    feat_vals(k, :) = feat.data(fly_feature, LungeEnds(k)+1:LungeEnds(k)+num_frames, mask_cell{j});
                else
                    feat_vals(k, :) = feat.data(fly_feature, LungeStarts(k)+num_frames:LungeStarts(k)-1, mask_cell{j});
                end
            end
            featAll(featAll_sz).(feat_name{j}) = feat_vals;
        end

        feat_temp_cell = cellfun(@(name) featAll(1).(name), feat_name, 'UniformOutput', false);
        featAll(featAll_sz).table = table(feat_temp_cell{:}, 'VariableNames', feat_name);
    end
    
    for i=1:length(featAll)
        for j=1:length(feat_name)
            featAll(i).(strcat(feat_name{j}, '_mean')) = mean(featAll(i).(feat_name{j}), 2);
            featAll(i).(strcat(feat_name{j}, '_var')) = var(featAll(i).(feat_name{j}), 0, 2);
            featAll(i).(strcat(feat_name{j}, '_init')) = featAll(i).(feat_name{j})(:, 1);
            featAll(i).(strcat(feat_name{j}, '_end')) = featAll(i).(feat_name{j})(:, end);
            featAll(i).(strcat(feat_name{j}, '_delta')) = featAll(i).(feat_name{j})(:, end) - featAll(i).(feat_name{j})(:, 1);
        end
    end
    
    % Remove sequences that have
    % more lunge happening in the duration designated by num_frames    
    featAll_fields = fieldnames(featAll);
    for i=1:length(featAll)
        featAll(i).inter_lunge_interval = featAll(i).lunge_starts(2:end) - featAll(i).lunge_ends(1:end-1);
        if isempty(featAll(i).inter_lunge_interval)
            continue;
        end
        if num_frames > 0
            period_mask = [featAll(i).inter_lunge_interval < num_frames; false];
        else
            period_mask = [false; featAll(i).inter_lunge_interval < abs(num_frames)];
        end
        for k=1:length(featAll_fields)
            if contains(featAll_fields{k}, {'movie', 'fly', 'genotype', 'table'})
                continue; 
            else
                featAll(i).(featAll_fields{k})(period_mask, :) = [];
            end
        end
    end
    
    % Remove outlier sequences using quartile method
    num_of_outliers = 0;
    for j=1:length(feat_name)
        if contains(feat_name{j}, {'angle', 'mutual'})
            continue;
        end
        curr_feature_all_means = vertcat(featAll(:).(strcat(feat_name{j}, '_mean'))); 
        quartiles = quantile(curr_feature_all_means, [0.25, 0.75]);
        iqr_of_means = quartiles(2) - quartiles(1); 
        outlier_mask = bitor((quartiles(1) - curr_feature_all_means) > 1.5*iqr_of_means, ...
            (curr_feature_all_means - quartiles(2)) > 1.5*iqr_of_means); 
        num_of_outliers = num_of_outliers + sum(outlier_mask);
        outlier_mask_by_fly_cell = mat2cell(outlier_mask, arrayfun(@(s) length(s.(strcat(feat_name{j}, '_mean'))), featAll));
        for i=1:length(outlier_mask_by_fly_cell)
            for k=1:length(featAll_fields)
                if contains(featAll_fields{k}, {'movie', 'fly', 'genotype', 'table'})
                    continue; 
                else
                    featAll(i).(featAll_fields{k})(outlier_mask_by_fly_cell{i}, :) = [];
                end
            end
        end
    end
    if num_frames > 0
        opt_str = 'post-lunge';
    else
        opt_str = 'pre-lunge';
    end
    fprintf('Removed %d outliers; %d %s sequences remaining\n', num_of_outliers, length(vertcat(featAll(:).(strcat(feat_name{j}, '_mean')))), opt_str);

    if check_attacked_fly
        fly_str = 'attacked';
    else
        fly_str = 'attacking';
    end
    save(fullfile(sprintf('FeatAll_%s_period_%d_%s_fly_genotype_%s-remove_outliers.mat', flymat_name, num_frames, fly_str, strjoin(cellstr(num2str(selected_genotype')), '_'))), 'featAll');
    
%     figure();
%     hold on;
%     for i=1:length(featAll)
%         if  length(feat_name) == 1
%             for j=1:size(featAll(i).(feat_name{1}), 1)
%                 plot(featAll(i).(feat_name{1})(j, :) - featAll(i).(strcat(feat_name{1}, '_init'))(j));
%             end
%         elseif length(feat_name) == 2 
%             for j=1:size(featAll(i).(feat_name{1}), 1)
%                 plot(featAll(i).(feat_name{1})(j,:) - featAll(i).(strcat(feat_name{1}, '_init'))(j), ...
%                     featAll(i).(feat_name{2})(j, :) - featAll(i).(strcat(feat_name{2}, '_init'))(j));
%             end
%         elseif length(feat_name) == 3
%             for j=1:size(featAll(i).(feat_name{1}), 1)
%                 plot3(featAll(i).(feat_name{1})(j,:) - featAll(i).(strcat(feat_name{1}, '_init'))(j), ...
%                     featAll(i).(feat_name{2})(j,:) - featAll(i).(strcat(feat_name{2}, '_init'))(j), ...
%                     featAll(i).(feat_name{3})(j,:) - featAll(i).(strcat(feat_name{3}, '_init'))(j));
%             end
%         else
%             fprintf('Can only visualize 1 to 3 features\n');
%         end
%     end
%     hold off;
%     if  length(feat_name) == 1
%         xlabel('Time (frame)');
%         ylabel(strrep(feat_name{1}, '_', '-'));
%     elseif  length(feat_name) == 2 
%         xlabel(strrep(feat_name{1}, '_', '-'));
%         ylabel(strrep(feat_name{2}, '_', '-'));
%     else
%         xlabel(strrep(feat_name{1}, '_', '-'));
%         ylabel(strrep(feat_name{2}, '_', '-'));
%         zlabel(strrep(feat_name{3}, '_', '-'));
%     end
%     
%     if length(feat_name) == 1
% %         saveas(double(gcf), fullfile(common_path,strcat(flymat_name, 'FeatAftLunge_', feat_name{1}, '.eps')));
%         saveas(double(gcf), fullfile(strcat(flymat_name, 'FeatAftLunge_', feat_name{1}, '.png')));
%     else
% %         saveas(double(gcf), fullfile(common_path,strcat(flymat_name, 'FeatAftLunge_', strjoin(feat_name, '_'), '.eps')));
%         saveas(double(gcf), fullfile(strcat(flymat_name, 'FeatAftLunge_', strjoin(feat_name, '_'), '.png')));
%     end
    
    feat_probs = cell(length(feat_name), length(hist_stat));
    feat_prob_edges = cell(length(feat_name), length(hist_stat));
    for i=1:length(feat_name)
        for j=1:length(hist_stat)
            % figure();
            % hist_stat can be one or more in 'mean', 'var', 'init', 'end', 'delta'
            feat_stat = {featAll(:).(strcat(feat_name{i}, '_', hist_stat{j}))};
            feat_stat_zscore = zscore(vertcat(feat_stat{:}));
            if regexp(feat_name{i}, 'angle')
                bin_width = 0.1; 
            elseif regexp(feat_name{i}, 'dist')
                bin_width = 1;
            elseif regexp(feat_name{i}, 'vel')
                bin_width = 10; 
            end

            if regexp(hist_stat{j}, 'var')
                bin_width = bin_width^2; 
            end
            % histogram(vertcat(feat_stat{:}), 'BinWidth', bin_width)
            [feat_probs{i, j}, feat_prob_edges{i, j}] = histcounts(vertcat(feat_stat_zscore), 'BinWidth', bin_width, 'Normalization', 'probability');

%             if length(feat_name) == 1
%                 saveas(double(gcf), fullfile(common_path,strcat(flymat_name, 'FeatAftLunge_hist_', strcat(feat_name{1}, '_', hist_stat{j}), '.eps')));
%                 saveas(double(gcf), fullfile(strcat(flymat_name, 'FeatAftLunge_hist_', strcat(feat_name{1}, '_', hist_stat{j}), '.png')));
%             else
%                 saveas(double(gcf), fullfile(common_path,strcat(flymat_name, 'FeatAftLunge_hist_', strcat(feat_name{i}, '_', hist_stat{j}), '.eps')));
%                 saveas(double(gcf), fullfile(strcat(flymat_name, 'FeatAftLunge_hist_', strcat(feat_name{i}, '_', hist_stat{j}), '.png')));
%             end
        end
    end
end