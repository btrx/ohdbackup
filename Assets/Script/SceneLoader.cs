using UnityEngine;
using UnityEngine.SceneManagement;
using System.Collections;

// Shows a loading screen, then loads a scene in the background.
// Hook LoadAR() (or LoadScene with a name) to a button instead of the old direct LoadScene call.
public class SceneLoader : MonoBehaviour
{
    // [SerializeField] GameObject loadingScreen;   // full-screen panel that holds the LoadingSpinner
    // [SerializeField] float minSeconds = 1.2f;    // keep the loader visible at least this long

    void Start()
    {
        // // keep the loading screen hidden until a load actually starts
        // if (loadingScreen != null) loadingScreen.SetActive(false);
    }

    // convenience hook for the "Enter AR" button
    public void LoadAR() => LoadScene("ARScene3");
    public void LoadAR2() => LoadScene("ARScene2");

    public void LoadScene(string sceneName)
    {
        SceneManager.LoadScene(sceneName);
    }

    // IEnumerator LoadRoutine(string sceneName)
    // {
    //     // if (loadingScreen != null) loadingScreen.SetActive(true);

    //     float start = Time.unscaledTime;
    //     AsyncOperation op = SceneManager.LoadSceneAsync(sceneName);
    //     op.allowSceneActivation = false;

    //     // progress reaches 0.9 when the scene is ready; also wait out the minimum time
    //     while (op.progress < 0.9f || Time.unscaledTime - start < minSeconds)
    //         yield return null;

    //     op.allowSceneActivation = true;
    // }
}
