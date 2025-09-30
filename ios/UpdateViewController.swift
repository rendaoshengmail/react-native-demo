import UIKit

/// 一个简单的视图控制器，用于在热更新检查和下载过程中显示。
/// 它包含一个活动指示器和一个状态标签。
class UpdateViewController: UIViewController {

    private lazy var activityIndicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .large)
        indicator.color = .gray
        indicator.translatesAutoresizingMaskIntoConstraints = false
        return indicator
    }()
    
    private lazy var statusLabel: UILabel = {
        let label = UILabel()
        label.text = "正在检查更新，请稍候..."
        label.textColor = .darkGray
        label.font = .systemFont(ofSize: 16)
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white

        view.addSubview(activityIndicator)
        view.addSubview(statusLabel)

        setupConstraints()
        
        activityIndicator.startAnimating()
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            activityIndicator.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            activityIndicator.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            
            statusLabel.topAnchor.constraint(equalTo: activityIndicator.bottomAnchor, constant: 20),
            statusLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        ])
    }
}
