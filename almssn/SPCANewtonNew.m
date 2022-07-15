
classdef SPCANewtonNew
properties
    n
    r
    A
    mu
    algname
    Sv
    manifold
    retraction
    maxcg_iter
    X
    Y
    U
    gX
    gY
    gU
    LS

    minGX_ind
    minGX
    rec_c
    rec_X
    rec_Y
    rec_U
    rec_sigma
    rec_cg_regularizer
    rec_gradnorm

    loss
    sparse
    sigma
    iter_num
    residual
    cg_regularizer
    record
    tau
    feps
    maxinner_iter
    maxinner_iter_lim
    maxnewton_iter
    gradnorm
    gradnorm_decay
    gradnorm_min
    sigma_factor
    elapsed_time
    verbose
end

methods
    function ret = mul_AtA(obj, X)
        ret = X * obj.A' * obj.A;
    end

    function ret = AtA_mul(obj, X)
        ret = obj.A' * (obj.A * X);
    end

    function ret = l1_prox(obj, X, lam)
        ret = sign(X) .* max(0, abs(X) - lam);
    end

    function ret = l1_moreau(obj, X, lam)
        p = (abs(X) < lam);
        ret = p .* (0.5 * X .* X) + (1 - p) .* (lam * abs(X) - 0.5 * lam * lam);
    end

    function ret = objective_smooth(obj, X)
        ret = -sum(sum(X .* obj.AtA_mul(X)));
    end

    function ret = objective(obj, X)
        ret = obj.objective_smooth(X) + obj.mu * sum(sum(abs(X)));
    end

    function G = egrad(obj, X)
        T = X + obj.U / obj.sigma;
        G = -2 * obj.AtA_mul(X) + obj.sigma * (T - obj.l1_prox(T, obj.mu / obj.sigma));
    end

    function G = rgrad(obj, X)
        G = obj.manifold.proj(X, obj.egrad(X));
    end

    function DzG = ehess(obj, X, Z)
        T = X + obj.U / obj.sigma;
        E = (abs(T) <= obj.mu / obj.sigma);
        DzG = -2 * obj.AtA_mul(Z) + obj.sigma * Z .* E;
    end

    function H = rhess(obj, X, Z)
        H = obj.manifold.ehess2rhess(X, obj.egrad(X), obj.ehess(X, Z), Z);
    end

    function [Z, norm_res, it, flag, eig_min] = solve_newton_system_cg(obj, X, G, max_iter, tol, regularizer)
        metric = @(U, V) sum(sum(U .* V));
        Z = zeros(size(G));
        R = G;
        P = -R;
        eig_min = 1e10;
        flag = 1;

        for it = 1:max_iter
            norm_rr = metric(R, R);
            if sqrt(norm_rr) < tol
                break;
            end

            Hp = obj.rhess(X, P) + regularizer * P;
            norm_pp = metric(P, P);
            norm_pHp = metric(P, Hp);
            eig_min = min(eig_min, norm_pHp / norm_pp);

            % find small, or negative direction
            if norm_pHp < 1.0e-6 * norm_pp
                flag = 1;
                if norm_pHp < -1.0e-6 * norm_pp 
                    if obj.verbose
                        fprintf(' CG, Find Non-PSD\n');
                    end
                    flag = 0;
                else
                    if obj.verbose
                        fprintf(' CG, Term\n');
                    end
                    flag = -1;
                end
                break;
            end

            alpha = norm_rr / norm_pHp;
            Z = Z + alpha * P;
            R = alpha * Hp + R;
            beta = metric(R, R) / norm_rr;
            P = beta * P - R;
        end

        norm_res = sqrt(norm_rr);
    end

    function ret = alm_cost(obj, X, sigma, u)
        G = sigma * obj.l1_moreau(X + u / sigma, obj.mu / sigma);
        f = obj.objective_smooth(X);
        ret = f + sum(sum(G));
    end

    function ret = alm_costgrad(obj, X, sigma, u)
        T = X + u / sigma;
        ret = -2 * obj.AtA_mul(X) + sigma * (T - obj.l1_prox(T, obj.mu / sigma));
    end

    function [F, G] = alm_cost_costgrad(obj, X, sigma, u)
        F = obj.alm_cost(X, sigma, u);
        G = obj.alm_costgrad(X, sigma, u);
    end

    function obj = subopt_newton(obj, sigma, u)
        cost = @(X) obj.alm_cost(X, sigma, u);
        g_cost = @(X) obj.alm_costgrad(X, sigma, u);
        cost_and_grad = @(X) obj.alm_cost_costgrad(X, sigma, u);

        if obj.iter_num == 1
            X = zeros([obj.n, obj.r]);
            r = obj.r;
            X(1:r, 1:r) = eye(r);
        else
            X = obj.X;
        end

        if obj.verbose
            fprintf('=== Find initial point ===\n');
        end
        problem.M = obj.manifold;
        problem.cost = cost;
        problem.egrad = g_cost;

        % checkgradient(problem);

        gX = obj.manifold.proj(X, g_cost(X));

        if sqrt(sum(sum(gX .^ 2))) > obj.feps
            x_init = obj.X;

            options_sd.maxiter = obj.maxinner_iter;
            if obj.iter_num < 5
                options_sd.maxiter = options_sd.maxiter * 3;
            end
            options_sd.tolgradnorm = max(obj.gradnorm, obj.feps);
            options_sd.verbosity = obj.verbose;

            options_sd.record = 0;
            options_sd.mxitr = options_sd.maxiter;
            options_sd.gtol = options_sd.tolgradnorm;
            options_sd.xtol = 1.0e-20;
            options_sd.ftol = 1.0e-20;

%            Lu = (obj.Sv + obj.sigma) ^ 2 * 2; % + obj.sigma ^ 2;
            Lu = obj.Sv ^ 2 + obj.sigma;
            gfhandle = @(X) obj.manifold.proj(X, g_cost(X));

            [X, info] = OptStiefelGBB(x_init, cost_and_grad, options_sd);
            if obj.verbose
                fprintf('\nOptM: obj: %7.6e, itr: %d, nfe: %d, norm(XT*X-I): %3.2e \n', ...
                        info.fval, info.itr, info.nfe, norm(X'*X - eye(obj.r), 'fro') );
            end
        end

        gX = obj.manifold.proj(X, g_cost(X));

        if obj.iter_num <= 1 || (sqrt(sum(sum(gX .^ 2))) > obj.feps && obj.record.is_newton(obj.iter_num-1) == 0)
            obj.record.is_newton = [obj.record.is_newton 0];
            obj.X = X;
            return
        end

        X_old = X;

        if obj.verbose
            fprintf('=== Second-order algorithm ===\n');
            fprintf('    #%d, |gX|_2 = %g, cost = %g, norm_rr = N/A, alpha = N/A \n', 0, sqrt(sum(sum(gX .^ 2))), cost(X));
        end

        cur_regularizer = obj.cg_regularizer;
        newton_flag = 0;

        for it = 1:obj.maxnewton_iter
            gX_norm = sqrt(sum(sum(gX .^ 2)));
            if gX_norm < obj.gradnorm
                break;
            end

            [Z, norm_rr, it_newton, cg_flag, cg_eigmin] = obj.solve_newton_system_cg(X, gX, obj.maxcg_iter, min(1.0e-5, obj.gradnorm), cur_regularizer);
            lower_eig = -1.5 * min(cg_eigmin - cur_regularizer - 1.0e-5, 0);

            if cg_flag == -1 || norm_rr > 1.0e4 || isnan(sum(sum(abs(gX))))
                X = X_old;
                obj.feps = obj.feps * 0.8;
                break;
            end

            % update next initial cg_regularizer
            if cg_flag == 1 && ~newton_flag
                newton_flag = 1;
                decay_factor = 0.8;
                obj.cg_regularizer = max(lower_eig, obj.cg_regularizer * decay_factor);
            end

            prev_regularizer = cur_regularizer;
            if cg_flag <= 0
                cur_regularizer = cur_regularizer * 2;
                obj.cg_regularizer = max(obj.cg_regularizer, cur_regularizer);
                continue;
            else
                cur_regularizer = cur_regularizer * 0.7;
            end
            cur_regularizer = max(lower_eig, cur_regularizer);

            prev_X = X;
            alpha = 1.0;

            alpha_thres = 1.0e-4;
            tX = obj.retraction(X, Z);
            if obj.LS == 2
                while sum(sum(obj.manifold.proj(tX, g_cost(tX)).^2)) > (1 - 0.1 * alpha) * sum(sum(gX.^2)) && alpha > alpha_thres
                    alpha = alpha * 0.5;
                    tX = obj.retraction(X, alpha * Z);
                end
            else
                lgX = sum(sum(obj.manifold.proj(X, g_cost(X)) .* Z));
                sqZ = sum(sum(Z .* Z));
                if -lgX < 1.0e-3 * (sqZ ^ 1.025) 
                    Z = -obj.manifold.proj(X, g_cost(X));
                end
                while cost(tX) > cost(X) + 0.1 * alpha * lgX && alpha > alpha_thres
                    alpha = alpha * 0.5;
                    tX = obj.retraction(X, alpha * Z);
                end
            end

            X = tX;
            gX = obj.manifold.proj(X, g_cost(X));

            if obj.verbose
                fprintf('    #%d, |gX|_2 = %g, cost = %g, norm_rr = %g, cg_iter = %d, regularizer = %g, eigmin = %g, alpha = %g \n',...
                    it + 1, sqrt(sum(sum(gX.^2))), cost(X), norm_rr, it_newton, prev_regularizer, cg_eigmin, alpha);
            end
            if alpha < alpha_thres
                break;
            end
        end

        if obj.verbose
            fprintf('    Newton iter #%d, |gX|_2 = %g\n', it, sqrt(sum(sum(gX.^2))));
        end
        if it < obj.maxnewton_iter
            obj.record.is_newton = [obj.record.is_newton 1];
        else
            if obj.verbose
                fprintf('    Failed Newton!\n')
            end
            obj.record.is_newton = [obj.record.is_newton 0];
            obj.feps = obj.feps * 0.5;
        end
        obj.X = X;
    end

    function obj = update(obj)
        obj.gradnorm = max(obj.gradnorm_min, obj.gradnorm_decay.^obj.iter_num);
        if obj.iter_num > 2
            gap_U = sqrt(sum(sum(obj.gU .^ 2)));
            gap_X = sqrt(sum(sum(obj.gX .^ 2)));
            obj.gradnorm = max(obj.gradnorm_min, min(obj.gradnorm, gap_U * 5));
        end
        obj = obj.subopt_newton(obj.sigma, obj.U);
        obj.Y = obj.l1_prox(obj.X + obj.U / obj.sigma, obj.mu / obj.sigma);
        obj.U = obj.U + obj.sigma * (obj.X - obj.Y);
        obj = obj.KKT();
        residual = max(max(abs(obj.X - obj.Y)));
        L = -0.5 * log10(sum(sum(obj.gX.^2))) + 0.5 * log10(sum(sum(obj.gU.^2)));
        if residual >= obj.tau * obj.residual && L > -1.4 || L > 0.4
            obj.sigma = obj.sigma * obj.sigma_factor;
            obj.sigma = max(obj.sigma, sum(sum(obj.U.^2))^0.51);
        end

        obj.residual = residual;
        obj.iter_num = obj.iter_num + 1;
        if obj.record.gX(end) < obj.minGX
            obj.minGX_ind = obj.iter_num;
            obj.minGX = obj.record.gX(end);
            obj.rec_X = obj.X;
            obj.rec_Y = obj.Y;
            obj.rec_U = obj.U;
            obj.rec_sigma = obj.sigma;
            obj.rec_cg_regularizer = obj.cg_regularizer;
            obj.rec_gradnorm = obj.gradnorm;
        end

        % ==== safeguard ====
        if obj.iter_num > 5
            if obj.record.gX(end) > obj.minGX * 50 || obj.iter_num - obj.minGX_ind > 15 || L < -2.0
                obj.rec_c = obj.rec_c + 1;
            end
            if obj.rec_c > 8 && obj.maxinner_iter < obj.maxinner_iter_lim
                obj.rec_c = 0;
                obj.maxinner_iter = min(obj.maxinner_iter_lim, ceil(obj.maxinner_iter * 1.4));
                obj.X = obj.rec_X;
                obj.Y = obj.rec_Y;
                obj.U = obj.rec_U;
                obj.sigma = obj.rec_sigma * 0.7;
                obj.cg_regularizer = obj.rec_cg_regularizer;
                obj.gradnorm = obj.rec_gradnorm;
                if obj.verbose
                    fprintf(' --> maxinner_iter = %d', obj.maxinner_iter);
                end
            end
        end

    end

    function obj = KKT(obj)
        obj.gX = -2 * obj.AtA_mul(obj.X) + obj.U;
        obj.gX = obj.manifold.proj(obj.X, obj.gX) / (sqrt(sum(sum(obj.X.^2))) + 1);
        zero_Y = (abs(obj.Y) < 1.0e-6);
        obj.gY = (1 - zero_Y) .* (obj.mu * sign(obj.Y) - obj.U) - zero_Y .* obj.l1_prox(obj.U, obj.mu);
        obj.gY = obj.gY / (sqrt(sum(sum(obj.Y.^2))) + 1);
        obj.gU = obj.X - obj.Y;
        obj.sparse = sum(sum(abs(obj.X) < 1.0e-6)) / (obj.n * obj.r);
        obj.loss = obj.objective(obj.X);
        obj.record.gX = [ obj.record.gX max(max(abs(obj.gX))) ];
        obj.record.gY = [ obj.record.gY max(max(abs(obj.gY))) ];
        obj.record.gU = [ obj.record.gU max(max(abs(obj.gU))) ];
        obj.record.gradnorm = [ obj.record.gradnorm obj.gradnorm ];
        obj.record.sigma = [ obj.record.sigma obj.sigma ];
        obj.record.sparse = [ obj.record.sparse obj.sparse ];
        obj.record.loss   = [ obj.record.loss obj.loss ];
        obj.record.time   = [ obj.record.time toc ];

        if obj.verbose
            fprintf('gX = %g, gY = %g, gU = %g, gradnorm = %g, loss = %g\n', ...
                max(max(abs(obj.gX))), max(max(abs(obj.gY))), max(max(abs(obj.gU))), obj.gradnorm, obj.loss);
        end
    end

    function obj = run(obj, tol)
        tic;
        for i = 1:300
            obj = obj.update();
            if obj.verbose
                fprintf("Iter = %d, sigma = %g, gap = %g, sparse = %f, time = %f\n", i, obj.sigma, max(max(abs(obj.X - obj.Y))), obj.sparse, toc);
            end
            if max(max(abs(obj.gU))) + max(max(abs(obj.gX))) < tol
                break
            end
        end
        time = toc;
        obj.elapsed_time = time;
        [fv, ind] = min(obj.record.gX);
        fprintf('%s:Iter ***  Fval *** CPU  **** sparsity *** opt_norm \n', obj.algname);
        print_format = ' %i     %1.5e    %1.2f     %1.4f            %1.3e    \n';
        fprintf(1,print_format, obj.iter_num, obj.record.loss(ind), time, obj.record.sparse(ind), obj.record.gX(ind));
    end

    function obj = init_rand(obj, A, options)
        obj.A = A;
        obj.mu = options.mu;
        obj.n = options.n;
        obj.r = options.r;
        obj.tau = options.tau;
        obj.Sv = svds(full(A), 1);
        obj.sigma = (obj.Sv ^ 2) * 3;
        obj.maxinner_iter = options.maxinner_iter;
        obj.maxinner_iter_lim = options.maxinner_iter * 4;
        obj.maxnewton_iter = options.maxnewton_iter;
        obj.gradnorm_decay = options.gradnorm_decay;
        obj.gradnorm_min = options.gradnorm_min;
        obj.sigma_factor = options.sigma_factor;
        obj.manifold = stiefelfactory(obj.n, obj.r);
        obj.feps = 8.0e-4;
        obj.verbose = options.verbose;
        obj.minGX = inf;
        obj.rec_c = 0;
        obj.LS = options.LS;

        obj.X = obj.manifold.rand();
        obj.Y = zeros([obj.n obj.r]);
        obj.U = zeros([obj.n obj.r]);
        obj.iter_num = 1;
        obj.residual = 1.0e10;
        obj.cg_regularizer = 3;

        if isfield(options, 'retraction')
            if options.retraction == "exp"
                obj.retraction = obj.manifold.exp;
            elseif options.retraction == "retr"
                obj.retraction = obj.manifold.retr;
            elseif options.retraction == "polar"
                obj.retraction = obj.manifold.retr_polar;
            else
                obj.retraction = obj.manifold.retr;
            end
        else
            obj.retraction = obj.manifold.retr;
        end

        if isfield(options, 'maxcg_iter')
            obj.maxcg_iter = options.maxcg_iter;
        else
            obj.maxcg_iter = 100;
        end

        if isfield(options, 'algname')
            obj.algname = options.algname;
        else
            obj.algname = 'ALMSSN';
        end


        obj.record.gX = [];
        obj.record.gY = [];
        obj.record.gU = [];
        obj.record.gradnorm = [];
        obj.record.sigma = [];
        obj.record.sparse = [];
        obj.record.loss = [];
        obj.record.time = [];
        obj.record.is_newton = [];

    end

    function obj = init(obj, A, options)
        obj = obj.init_rand(A, options);
        obj.U = zeros([obj.n obj.r]);
        obj.X = options.x_init;
        obj.Y = obj.l1_prox(obj.X + obj.U / obj.sigma, obj.mu / obj.sigma);
    end

end
end
